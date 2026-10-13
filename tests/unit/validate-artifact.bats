#!/usr/bin/env bats
# Unit tests for .claude/scripts/validate-artifact.sh (cycle-119 C10)

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PROJECT_ROOT}/.claude/scripts/validate-artifact.sh"
    TEST_TMPDIR="${BATS_TMPDIR:-/tmp}/validate-artifact-test-$$"
    mkdir -p "${TEST_TMPDIR}"
}

teardown() {
    rm -rf "${TEST_TMPDIR}"
}

skip_if_no_jq() {
    command -v jq &>/dev/null || skip "jq not installed"
}

# =============================================================================
# Usage errors
# =============================================================================

@test "validate-artifact: missing --type is a usage error (exit 2)" {
    touch "${TEST_TMPDIR}/f.md"
    run "$SCRIPT" --file "${TEST_TMPDIR}/f.md"
    [ "$status" -eq 2 ]
}

@test "validate-artifact: unknown --type is a usage error (exit 2)" {
    touch "${TEST_TMPDIR}/f.md"
    run "$SCRIPT" --type bogus --file "${TEST_TMPDIR}/f.md"
    [ "$status" -eq 2 ]
}

@test "validate-artifact: nonexistent file is a usage error (exit 2)" {
    run "$SCRIPT" --type prd --file "${TEST_TMPDIR}/nope.md"
    [ "$status" -eq 2 ]
}

@test "validate-artifact: --help exits 0" {
    run "$SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

# =============================================================================
# prd
# =============================================================================

@test "validate-artifact prd: passes when every '## ' section has '> Sources:'" {
    cat > "${TEST_TMPDIR}/prd.md" <<'EOF'
## 1. Problem Statement

Some text. [ASSUMPTION] users have internet.

> Sources: vision.md:12-15

## 2. Goals

> Sources: interview notes
EOF
    run "$SCRIPT" --type prd --file "${TEST_TMPDIR}/prd.md"
    [ "$status" -eq 0 ]
}

@test "validate-artifact prd: fails when a section has no '> Sources:' line" {
    cat > "${TEST_TMPDIR}/prd.md" <<'EOF'
## 1. Problem Statement

No sources here.

## 2. Goals

> Sources: ok
EOF
    run "$SCRIPT" --type prd --file "${TEST_TMPDIR}/prd.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Problem Statement"* ]]
    [[ "$output" == *"Sources"* ]]
}

@test "validate-artifact prd: --json reports the [ASSUMPTION] tag count as info" {
    skip_if_no_jq
    cat > "${TEST_TMPDIR}/prd.md" <<'EOF'
## 1. Problem

[ASSUMPTION] one. [ASSUMPTION] two.

> Sources: x
EOF
    run "$SCRIPT" --type prd --file "${TEST_TMPDIR}/prd.md" --json
    [ "$status" -eq 0 ]
    [[ "$(echo "$output" | jq -r '.info[0]')" == *"2"* ]]
}

# =============================================================================
# sdd
# =============================================================================

sdd_all_sections() {
    cat <<'EOF'
## 1. Project Architecture
x
## 2. Software Stack
x
## 3. Database Design
x
## 4. UI Design
x
## 5. API Specifications
x
## 6. Error Handling Strategy
x
## 7. Testing Strategy
x
## 8. Development Phases
x
## 9. Known Risks and Mitigation
x
## 10. Open Questions
x
EOF
}

@test "validate-artifact sdd: passes when all 10 required sections are present" {
    sdd_all_sections > "${TEST_TMPDIR}/sdd.md"
    run "$SCRIPT" --type sdd --file "${TEST_TMPDIR}/sdd.md"
    [ "$status" -eq 0 ]
}

@test "validate-artifact sdd: fails and names every missing required section" {
    cat > "${TEST_TMPDIR}/sdd.md" <<'EOF'
## 1. Project Architecture
x
## 2. Software Stack
x
EOF
    run "$SCRIPT" --type sdd --file "${TEST_TMPDIR}/sdd.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Database Design"* ]]
    [[ "$output" == *"Open Questions"* ]]
}

@test "validate-artifact sdd: WARNs (does not fail) on a bare framework name with no version" {
    sdd_all_sections > "${TEST_TMPDIR}/sdd.md"
    echo "We also use React for the frontend." >> "${TEST_TMPDIR}/sdd.md"
    run "$SCRIPT" --type sdd --file "${TEST_TMPDIR}/sdd.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"React"* ]]
}

@test "validate-artifact sdd: does not WARN when a version-shaped token is on the same line" {
    sdd_all_sections > "${TEST_TMPDIR}/sdd.md"
    echo "We use React 18.2 for the frontend." >> "${TEST_TMPDIR}/sdd.md"
    run "$SCRIPT" --type sdd --file "${TEST_TMPDIR}/sdd.md"
    [ "$status" -eq 0 ]
    [[ "$output" != *"'React'"* ]]
}

# =============================================================================
# sprint
# =============================================================================

sprint_block() {
    local heading="$1"
    cat <<EOF
$heading

### Sprint Goal
g

### Deliverables
- [ ] d

### Acceptance Criteria
- [ ] c

### Technical Tasks
- [ ] Task → **[G-1]**

### Dependencies
- none

### Security Considerations
- none

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| r | Low | Low | m |

### Success Metrics
- m
EOF
}

@test "validate-artifact sprint: passes with all required sections, goal coverage, and E2E in final sprint" {
    {
        sprint_block "## Sprint 1: Foundation"
        echo
        cat <<'EOF'
## Sprint 2 (Final): Wrap-up

### Sprint Goal
finish

### Deliverables
- [ ] d

### Acceptance Criteria
- [ ] c

### Technical Tasks
- [ ] Task 2.E2E: End-to-End Goal Validation → **[G-1]**

### Dependencies
- Sprint 1

### Security Considerations
- none

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| r | Low | Low | m |

### Success Metrics
- m

## Appendix

| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---|---|---|---|
| G-1 | thing | Sprint 1 | Sprint 2 |
EOF
    } > "${TEST_TMPDIR}/sprint.md"
    run "$SCRIPT" --type sprint --file "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 0 ]
}

@test "validate-artifact sprint: fails and names every missing required section in a block" {
    cat > "${TEST_TMPDIR}/sprint.md" <<'EOF'
## Sprint 1: Foundation

### Sprint Goal
g

### Deliverables
- [ ] d

## Appendix
| Goal ID | Goal Description |
|---|---|
EOF
    run "$SCRIPT" --type sprint --file "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Acceptance Criteria"* ]]
    [[ "$output" == *"Success Metrics"* ]]
}

@test "validate-artifact sprint: fails when a referenced goal ID is missing from the Appendix" {
    {
        sprint_block "## Sprint 1: Foundation"
        echo
        echo "## Appendix"
        echo "| Goal ID | Goal Description |"
        echo "|---|---|"
    } > "${TEST_TMPDIR}/sprint.md"
    run "$SCRIPT" --type sprint --file "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"G-1"* ]]
    [[ "$output" == *"Appendix"* ]]
}

@test "issue-1243: goal coverage includes later appendices across intervening sections" {
    {
        sprint_block "## Sprint 1: Foundation"
        cat <<'EOF'
## Appendix A: Dependencies
No goal mapping here.
## Another section
G-2 is also required.
## Appendix C: Goal Traceability
| G-1 | Foundation |
## Interlude
This is not an appendix.
## Appendix C (cycle-002): Goal Traceability
| G-2 | Continuation |
EOF
    } > "${TEST_TMPDIR}/sprint.md"
    run "$SCRIPT" --type sprint --file "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 0 ]
}

@test "issue-1243: non-appendix mentions do not satisfy missing goal coverage" {
    {
        sprint_block "## Sprint 1: Foundation"
        cat <<'EOF'
## Appendix A: Dependencies
No goal mapping here.
## Another section
| G-1 | Outside the appendix |
## Appendix C: Goal Traceability
| G-2 | Other goal |
EOF
    } > "${TEST_TMPDIR}/sprint.md"
    run "$SCRIPT" --type sprint --file "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"goal ID G-1"* ]]
}

@test "issue-1243: G-10 does not satisfy a missing G-1 mapping" {
    {
        sprint_block "## Sprint 1: Foundation"
        printf '\n## Appendix\n| G-10 | Another goal |\n'
    } > "${TEST_TMPDIR}/sprint.md"
    run "$SCRIPT" --type sprint --file "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"goal ID G-1"* ]]
}

@test "issue-1243: large combined appendices do not turn an early goal match into SIGPIPE failure" {
    {
        local i
        for i in $(seq 1 50); do
            sprint_block "## Sprint $i: Foundation"
            printf '\n## Appendix C: Goal Traceability\n| G-1 | Foundation |\n'
            # Each sprint block stays small; the combined appendix text
            # exceeds the pipe buffer and grep may finish before printf.
            printf '%3000s\n' 'Appendix commentary.'
        done
    } > "${TEST_TMPDIR}/sprint.md"
    run "$SCRIPT" --type sprint --file "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 0 ]
}

@test "validate-artifact sprint: WARNs (does not fail) when the final sprint has no E2E task" {
    {
        sprint_block "## Sprint 1: Foundation"
        echo
        echo "## Appendix"
        echo "| Goal ID | Goal Description |"
        echo "|---|---|"
        echo "| G-1 | thing |"
    } > "${TEST_TMPDIR}/sprint.md"
    run "$SCRIPT" --type sprint --file "${TEST_TMPDIR}/sprint.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"E2E"* ]]
}

# =============================================================================
# bug-triage
# =============================================================================

@test "validate-artifact bug-triage: passes with a valid bug_id and a schema_version'd state.json" {
    mkdir -p "${TEST_TMPDIR}/root/.run/bugs/20260707-a3f2b1"
    echo '{"schema_version": 1, "bug_id": "20260707-a3f2b1"}' > "${TEST_TMPDIR}/root/.run/bugs/20260707-a3f2b1/state.json"
    cat > "${TEST_TMPDIR}/triage.md" <<'EOF'
## Metadata
- **schema_version**: 1
- **bug_id**: 20260707-a3f2b1
EOF
    PROJECT_ROOT="${TEST_TMPDIR}/root" run "$SCRIPT" --type bug-triage --file "${TEST_TMPDIR}/triage.md"
    [ "$status" -eq 0 ]
}

@test "validate-artifact bug-triage: fails on a malformed bug_id" {
    cat > "${TEST_TMPDIR}/triage.md" <<'EOF'
- **bug_id**: not-a-valid-id
EOF
    PROJECT_ROOT="${TEST_TMPDIR}/root" run "$SCRIPT" --type bug-triage --file "${TEST_TMPDIR}/triage.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not match the bug-triaging ID grammar"* ]]
}

@test "validate-artifact bug-triage: fails when the sibling state.json is missing" {
    cat > "${TEST_TMPDIR}/triage.md" <<'EOF'
- **bug_id**: 20260707-a3f2b1
EOF
    PROJECT_ROOT="${TEST_TMPDIR}/root" run "$SCRIPT" --type bug-triage --file "${TEST_TMPDIR}/triage.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"state.json not found"* ]]
}

@test "validate-artifact bug-triage: fails when state.json has no schema_version" {
    mkdir -p "${TEST_TMPDIR}/root/.run/bugs/20260707-a3f2b1"
    echo '{"bug_id": "20260707-a3f2b1"}' > "${TEST_TMPDIR}/root/.run/bugs/20260707-a3f2b1/state.json"
    cat > "${TEST_TMPDIR}/triage.md" <<'EOF'
- **bug_id**: 20260707-a3f2b1
EOF
    PROJECT_ROOT="${TEST_TMPDIR}/root" run "$SCRIPT" --type bug-triage --file "${TEST_TMPDIR}/triage.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no schema_version"* ]]
}

# =============================================================================
# translation (C-D5, cycle-120)
# =============================================================================

@test "validate-artifact translation: resolving parenthesized citation passes" {
    mkdir -p "${TEST_TMPDIR}/root/grimoires/loa"
    printf 'line1\nline2\nline3\n' > "${TEST_TMPDIR}/root/grimoires/loa/drift-report.md"
    cat > "${TEST_TMPDIR}/exec-index.md" <<'EOF'
## Finding

Drift confirmed (drift-report.md:L2).
EOF
    PROJECT_ROOT="${TEST_TMPDIR}/root" run "$SCRIPT" --type translation --file "${TEST_TMPDIR}/exec-index.md"
    [ "$status" -eq 0 ]
}

@test "validate-artifact translation: resolving bare table-cell citation passes" {
    mkdir -p "${TEST_TMPDIR}/root/grimoires/loa"
    printf 'line1\nline2\nline3\n' > "${TEST_TMPDIR}/root/grimoires/loa/drift-report.md"
    cat > "${TEST_TMPDIR}/audit.md" <<'EOF'
| Component | Value | Source |
|-----------|-------|--------|
| Drift | 34% | drift-report.md:L2 |
EOF
    PROJECT_ROOT="${TEST_TMPDIR}/root" run "$SCRIPT" --type translation --file "${TEST_TMPDIR}/audit.md"
    [ "$status" -eq 0 ]
}

@test "validate-artifact translation: fails when a cited path does not resolve" {
    mkdir -p "${TEST_TMPDIR}/root/grimoires/loa"
    cat > "${TEST_TMPDIR}/exec-index.md" <<'EOF'
## Finding

Ghost feature found (nonexistent-report.md:L1).
EOF
    PROJECT_ROOT="${TEST_TMPDIR}/root" run "$SCRIPT" --type translation --file "${TEST_TMPDIR}/exec-index.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CITATION UNRESOLVED"* ]]
    [[ "$output" == *"nonexistent-report.md:L1"* ]]
}

@test "validate-artifact translation: fails when the cited line is out of range" {
    mkdir -p "${TEST_TMPDIR}/root/grimoires/loa"
    printf 'line1\nline2\nline3\n' > "${TEST_TMPDIR}/root/grimoires/loa/drift-report.md"
    cat > "${TEST_TMPDIR}/exec-index.md" <<'EOF'
## Finding

Drift confirmed (drift-report.md:L50).
EOF
    PROJECT_ROOT="${TEST_TMPDIR}/root" run "$SCRIPT" --type translation --file "${TEST_TMPDIR}/exec-index.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CITATION LINE OUT OF RANGE"* ]]
    [[ "$output" == *"drift-report.md:L50"* ]]
}

@test "validate-artifact translation: skips {...}-placeholder citations" {
    mkdir -p "${TEST_TMPDIR}/root/grimoires/loa"
    cat > "${TEST_TMPDIR}/template.md" <<'EOF'
## Claim Format

Every claim must end with a citation (file:L##).
EOF
    PROJECT_ROOT="${TEST_TMPDIR}/root" run "$SCRIPT" --type translation --file "${TEST_TMPDIR}/template.md"
    [ "$status" -eq 0 ]
}

@test "validate-artifact translation: skips markdown-link / URL citation forms" {
    mkdir -p "${TEST_TMPDIR}/root/grimoires/loa"
    cat > "${TEST_TMPDIR}/exec-index.md" <<'EOF'
## Finding

See [the drift report](https://internal.example.com/reports/drift-report.md:L999) for detail.
Also see https://internal.example.com/reports/drift-report.md:L999 directly.
EOF
    PROJECT_ROOT="${TEST_TMPDIR}/root" run "$SCRIPT" --type translation --file "${TEST_TMPDIR}/exec-index.md"
    [ "$status" -eq 0 ]
}

@test "validate-artifact translation: resolves a citation under grimoires/loa/reality/ (hygiene-report.md)" {
    mkdir -p "${TEST_TMPDIR}/root/grimoires/loa/reality"
    printf 'line1\nline2\nline3\nline4\n' > "${TEST_TMPDIR}/root/grimoires/loa/reality/hygiene-report.md"
    cat > "${TEST_TMPDIR}/exec-index.md" <<'EOF'
## Finding

Untracked artifact found (hygiene-report.md:L2).
EOF
    PROJECT_ROOT="${TEST_TMPDIR}/root" run "$SCRIPT" --type translation --file "${TEST_TMPDIR}/exec-index.md"
    [ "$status" -eq 0 ]
}

@test "validate-artifact translation: WARNs when the stated Health Score mismatches the recompute" {
    mkdir -p "${TEST_TMPDIR}/root/grimoires/loa/reality"
    echo '## Drift Score: 34%' > "${TEST_TMPDIR}/root/grimoires/loa/drift-report.md"
    echo '## Consistency Score: 6/10' > "${TEST_TMPDIR}/root/grimoires/loa/consistency-report.md"
    echo '## Hygiene Items: 23' > "${TEST_TMPDIR}/root/grimoires/loa/reality/hygiene-report.md"
    cat > "${TEST_TMPDIR}/exec-index.md" <<'EOF'
## Weighted Health Score

**Health Score: 90%** — calculated per the official formula.
EOF
    PROJECT_ROOT="${TEST_TMPDIR}/root" run "$SCRIPT" --type translation --file "${TEST_TMPDIR}/exec-index.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"HEALTH SCORE MISMATCH"* ]]
}

@test "validate-artifact translation: --file accepts a directory and validates every *.md" {
    mkdir -p "${TEST_TMPDIR}/root/grimoires/loa" "${TEST_TMPDIR}/translations"
    printf 'line1\nline2\nline3\n' > "${TEST_TMPDIR}/root/grimoires/loa/drift-report.md"
    cat > "${TEST_TMPDIR}/translations/a.md" <<'EOF'
Drift confirmed (drift-report.md:L2).
EOF
    cat > "${TEST_TMPDIR}/translations/b.md" <<'EOF'
Bad citation (nonexistent-report.md:L1).
EOF
    PROJECT_ROOT="${TEST_TMPDIR}/root" run "$SCRIPT" --type translation --file "${TEST_TMPDIR}/translations"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CITATION UNRESOLVED"* ]]
}

@test "validate-artifact translation: caps an over-2000-char line without hanging (cycle-120 R2)" {
    # A single very long path-dense line used to make the incremental citation
    # scan superlinear and hang the MUST gate. It must now be capped (WARN +
    # skip) and complete in bounded time.
    mkdir -p "${TEST_TMPDIR}/root/grimoires/loa"
    printf 'line1\nline2\n' > "${TEST_TMPDIR}/root/grimoires/loa/drift-report.md"
    {
        printf '# T\n'
        printf 'path/to/some/very/long/segment.md %.0s' $(seq 1 400)   # ~2600 chars, one line
        printf '\nDrift confirmed (drift-report.md:L2).\n'
    } > "${TEST_TMPDIR}/longline.md"
    PROJECT_ROOT="${TEST_TMPDIR}/root" run timeout 10 "$SCRIPT" --type translation --file "${TEST_TMPDIR}/longline.md"
    [ "$status" -ne 124 ]                       # not a timeout
    [[ "$output" == *"exceeds 2000 chars"* ]]   # the cap fired with its WARN
}

# =============================================================================
# bd-8ndx: under pipefail, `printf '%s' "$big" | grep -q` loses the race — grep
# exits on its first match, printf takes SIGPIPE, the pipeline returns 141 and
# `!` reads a present section as missing. The checks read here-strings instead.
# =============================================================================

filler() { awk 'BEGIN { for (i = 0; i < 40000; i++) print "- filler line " i " ................................................" }'; }

@test "validate-artifact sprint: a block far larger than a pipe buffer with its sections at the top passes (bd-8ndx)" {
    {
        sprint_block "## Sprint 1: Foundation"
        filler
        echo
        cat <<'EOF2'
## Sprint 2 (Final): Wrap-up

### Sprint Goal
finish

### Deliverables
- [ ] d

### Acceptance Criteria
- [ ] c

### Technical Tasks
- [ ] Task 2.E2E: End-to-End Goal Validation → **[G-1]**

### Dependencies
- Sprint 1

### Security Considerations
- none

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| r | Low | Low | m |

### Success Metrics
- m
EOF2
        filler
        cat <<'EOF2'

## Appendix

| Goal ID | Goal Description | Contributing Tasks | Validation Task |
|---|---|---|---|
| G-1 | thing | Sprint 1 | Sprint 2 |
EOF2
    } > "${TEST_TMPDIR}/sprint.md"
    local i
    for i in 1 2 3; do
        run "$SCRIPT" --type sprint --file "${TEST_TMPDIR}/sprint.md"
        [ "$status" -eq 0 ] || { echo "run $i: $output"; return 1; }
        [[ "$output" != *"missing required section"* && "$output" != *"no E2E"* && "$output" != *"Security Considerations"* ]]
    done
}

@test "validate-artifact prd: a section body far larger than a pipe buffer with '> Sources:' at the top passes (bd-8ndx)" {
    {
        printf '## 1. Problem Statement\n\n> Sources: vision.md:12-15\n\n'
        filler
    } > "${TEST_TMPDIR}/prd.md"
    local i
    for i in 1 2 3; do
        run "$SCRIPT" --type prd --file "${TEST_TMPDIR}/prd.md"
        [[ "$output" != *"has no '> Sources:' line"* ]] || { echo "run $i: $output"; return 1; }
    done
}

@test "validate-artifact: no check pipes a variable into grep -q (bd-8ndx)" {
    run grep -nE "printf '%s' \"\\\$[a-z_]+\" \| grep -q" "$SCRIPT"
    [ "$status" -eq 1 ]
}

# =============================================================================
# decisions (the decision ledger) + the prd tag-to-row rule + the sdd DEC column
# =============================================================================
# Hermetic: a temp project under BATS_TEST_TMPDIR holds a copy of the validator, the ledger writer
# and compat-lib, so the host's run state (a RUNNING run makes the context unattended) never leaks
# in. Fixtures are written by the writer, then mutated by yq as a hand edit would be.

_dec_skip_unless_tools() {
    skip_if_no_jq
    [[ "$(yq --version 2>&1)" == *mikefarah*"version v4."* ]] || skip "Mike Farah yq v4 not installed"
}

_dec_project() {
    unset LOA_UNATTENDED LOA_FLATLINE_MODE CI GITHUB_ACTIONS LOA_HOOK_CONTEXT CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID
    DP="$BATS_TEST_TMPDIR/dproj"
    mkdir -p "$DP/.claude/scripts/lib" "$DP/grimoires/loa"
    cp "$SCRIPT" "$PROJECT_ROOT/.claude/scripts/compat-lib.sh" "$DP/.claude/scripts/"
    [[ -f "$PROJECT_ROOT/.claude/scripts/pii-filter.sh" ]] && cp "$PROJECT_ROOT/.claude/scripts/pii-filter.sh" "$DP/.claude/scripts/"
    cp "$PROJECT_ROOT/.claude/scripts/lib/dec-write-lib.sh" "$DP/.claude/scripts/lib/"
    { sed '/^schema_version:/,$d' "$PROJECT_ROOT/grimoires/loa/decisions.yaml"; printf 'schema_version: 1\ndecisions: []\n'; } > "$DP/grimoires/loa/decisions.yaml"
    git -C "$DP" init -q
    DV="$DP/.claude/scripts/validate-artifact.sh"
    DW="$DP/.claude/scripts/lib/dec-write-lib.sh"
    DL="$DP/grimoires/loa/decisions.yaml"
    DALT='{"option":"keep sequential","rejected_because":"slow"}'
}
# _dec_rows N: N proposed rows in the fixture ledger; DEC-0001 confirmed by the operator when $1 == confirm
_dec_new_prop() { bash "$DW" new --file "$DL" --summary "${1:-rounds is the default}" --phase discovery --category scope --recorded-by t \
    --source "${2:-prd.md#e (D1)}" --status proposed --decision d --rationale r --alternative-json "$DALT" --cycle cycle-128 --quiet; }
_dec_confirm() { bash "$DW" confirm --file "$DL" --id "$1" --recorded-by decisions-command --evidence "cli:2026-10-13T12:00:00Z" --answer-ref "cli:2026-10-13T12:00:00Z" --quiet; }

@test "validate-artifact decisions: the live ledger passes" {
    _dec_skip_unless_tools
    run "$SCRIPT" --type decisions --file "$PROJECT_ROOT/grimoires/loa/decisions.yaml"
    [ "$status" -eq 0 ]
}

@test "validate-artifact decisions: a writer-built ledger passes (open, proposed, decided, rejected, superseded rows)" {
    _dec_skip_unless_tools; _dec_project
    _dec_new_prop >/dev/null; _dec_new_prop >/dev/null; _dec_new_prop >/dev/null
    _dec_confirm DEC-0001
    bash "$DW" reject --file "$DL" --id DEC-0002 --rationale no --follow-up bd-x --recorded-by t --quiet
    bash "$DW" supersede --file "$DL" --id DEC-0001 --summary s2 --phase discovery --category scope --recorded-by decisions-command --source s --decision d --rationale r --alternative-json "$DALT" --quiet >/dev/null
    run "$DV" --type decisions --file "$DL"
    [ "$status" -eq 0 ]
    [[ "$output" == *"4 decision rows"* ]]
}

# _dec_bad <yq mutation> <expected message fragment> [--base]
_dec_bad() {
    local expr="$1" want="$2" base="${3:-}"
    cp "$DL" "$BATS_TEST_TMPDIR/base.yaml"
    yq -i "$expr" "$DL"
    if [[ "$base" == "--base" ]]; then run "$DV" --type decisions --file "$DL" --base-file "$BATS_TEST_TMPDIR/base.yaml"
    else run "$DV" --type decisions --file "$DL"; fi
    [ "$status" -eq 1 ] || { echo "expected exit 1 for: $expr; got $status: $output"; return 1; }
    [[ "$output" == *"$want"* ]] || { echo "missing [$want] in: $output"; return 1; }
    cp "$BATS_TEST_TMPDIR/base.yaml" "$DL"
}

@test "validate-artifact decisions: each negative fixture exits 1 with its reason" {
    _dec_skip_unless_tools; _dec_project
    _dec_new_prop >/dev/null; _dec_new_prop >/dev/null; _dec_confirm DEC-0001
    _dec_bad 'del(.decisions[1].decided_by)' "DEC-0002: missing field decided_by"
    _dec_bad '.decisions += [.decisions[1]]' "duplicate id DEC-0002"
    _dec_bad '.decisions[1].id = "PEND-0a1b2c3d"' "PEND- id in the live ledger"
    _dec_bad '.decisions[0].transitions[1].evidence = ""' "the -> decided transition has no evidence"
    _dec_bad '.decisions[0].decided_by_ref = null' "decided_by operator needs an operator answer reference"
    _dec_bad '.decisions[0].transitions[1].by = "agent:run-mode"' "needs by operator:*"
    _dec_bad '.decisions[1].decided_by = "agent"' "decided_by must stay null until /decisions confirm"
    _dec_bad '.decisions[1].decided_by_ref = "trust me"' "does not match the ref grammar"
    _dec_bad '.schema_version = 2' "unknown schema_version 2"
    _dec_bad '.decisions[1].rationale = "see https://example.com/x"' "a URL in free text"
    _dec_bad '.decisions[1].phase = "whenever"' "phase \"whenever\" is not one of"
    _dec_bad '.decisions[1].alternatives_considered = []' "at least one alternatives_considered entry"
    _dec_bad '.decisions[1].transitions[0].from = "open"' "the first transition must be null -> open|proposed"
}

@test "validate-artifact decisions: an illegal transition (rejected -> decided) fails" {
    _dec_skip_unless_tools; _dec_project
    _dec_new_prop >/dev/null
    bash "$DW" reject --file "$DL" --id DEC-0001 --rationale no --follow-up bd-x --recorded-by t --quiet
    _dec_bad '.decisions[0].transitions += [{"at":"2026-10-14T00:00:00Z","from":"rejected","to":"decided","by":"operator:decisions-command","evidence":"cli:2026-10-14T00:00:00Z"}] | .decisions[0].status = "decided" | .decisions[0].decided_by = "operator" | .decisions[0].decided_by_ref = "cli:2026-10-14T00:00:00Z"' 'illegal transition "rejected" -> "decided"'
    _dec_bad '.decisions[0].follow_up = null' "a rejected row needs rejection_rationale and follow_up"
}

@test "validate-artifact decisions: content edits, dropped rows and rewritten history fail against the base; an appended transition passes" {
    _dec_skip_unless_tools; _dec_project
    _dec_new_prop >/dev/null; _dec_new_prop >/dev/null
    _dec_bad '.decisions[0].summary = "rewritten"' "DEC-0001: content edit to summary" --base
    _dec_bad '.decisions[1].source = "elsewhere"' "DEC-0002: content edit to source" --base
    _dec_bad 'del(.decisions[1])' "DEC-0002: dropped (rows are append-only)" --base
    _dec_bad '.decisions[0].transitions[0].evidence = "edited"' "DEC-0001: transitions rewritten" --base
    cp "$DL" "$BATS_TEST_TMPDIR/base.yaml"
    _dec_confirm DEC-0001
    run "$DV" --type decisions --file "$DL" --base-file "$BATS_TEST_TMPDIR/base.yaml"
    [ "$status" -eq 0 ]
}

@test "validate-artifact decisions: an operator row written under a live unattended signal fails" {
    _dec_skip_unless_tools; _dec_project
    _dec_new_prop >/dev/null
    cp "$DL" "$BATS_TEST_TMPDIR/base.yaml"
    _dec_confirm DEC-0001
    run env LOA_UNATTENDED=1 "$DV" --type decisions --file "$DL" --base-file "$BATS_TEST_TMPDIR/base.yaml"
    [ "$status" -eq 1 ]; [[ "$output" == *"decided_by operator written while a live unattended signal holds"* ]]
}

@test "validate-artifact decisions: supersede leaves the old row superseded and removes nothing" {
    _dec_skip_unless_tools; _dec_project
    _dec_new_prop >/dev/null; _dec_confirm DEC-0001
    cp "$DL" "$BATS_TEST_TMPDIR/base.yaml"
    run bash "$DW" supersede --file "$DL" --id DEC-0001 --summary s2 --phase discovery --category scope --recorded-by decisions-command --source s --decision d --rationale r --alternative-json "$DALT" --quiet
    [ "$status" -eq 0 ]
    [ "$(yq '.decisions | length' "$DL")" -eq 2 ]
    [ "$(yq '.decisions[0].status' "$DL")" = "superseded" ]
    run "$DV" --type decisions --file "$DL" --base-file "$BATS_TEST_TMPDIR/base.yaml"
    [ "$status" -eq 0 ]
    _dec_bad '.decisions[1].supersedes = "DEC-0042"' "supersedes DEC-0042 names no row"
}

# ---- prd: tag classes and the tag-to-row rule ------------------------------------------

_dec_prd() { # status-word date body...
    local st="$1" dt="$2"; shift 2
    { printf '# PRD\n\n**Date:** %s\n**Status:** %s\n\n## 1. Problem\n\n' "$dt" "$st"; printf '%s\n' "$@"; printf '\n> Sources: brief\n'; } > "$DP/grimoires/loa/prd.md"
}

@test "validate-artifact prd: an [ASSUMPTION decision] tag without a DEC row FAILS unattended and WARNs interactive" {
    _dec_skip_unless_tools; _dec_project
    _dec_prd "Draft (autonomous run)" 2026-10-13 "We take rounds. [ASSUMPTION decision] (DEC-0001)"
    run "$DV" --type prd --file "$DP/grimoires/loa/prd.md"
    [ "$status" -eq 1 ]; [[ "$output" == *"cites no DEC row whose source names prd.md"* ]]
    _dec_prd "Draft" 2026-10-13 "We take rounds. [ASSUMPTION decision] (DEC-0001)"
    run "$DV" --type prd --file "$DP/grimoires/loa/prd.md"
    [ "$status" -eq 0 ]; [[ "$output" == *"WARN:"*"cites no DEC row"* ]]
}

@test "validate-artifact prd: a cited row whose source names the PRD passes; one naming another file does not" {
    _dec_skip_unless_tools; _dec_project
    _dec_new_prop "rounds" "grimoires/loa/prd.md#appendix-e (D1)" >/dev/null
    _dec_new_prop "other" "grimoires/loa/sdd.md#11.3 (A1)" >/dev/null
    _dec_prd "Draft (unattended)" 2026-10-13 "Rounds. [ASSUMPTION decision] (DEC-0001)"
    run "$DV" --type prd --file "$DP/grimoires/loa/prd.md"
    [ "$status" -eq 0 ]; [[ "$output" != *"cites no DEC row"* ]]
    _dec_prd "Draft (unattended)" 2026-10-13 "Other. [ASSUMPTION decision] (DEC-0002)"
    run "$DV" --type prd --file "$DP/grimoires/loa/prd.md"
    [ "$status" -eq 1 ]
    # --ledger points the check at another ledger
    run "$DV" --type prd --file "$DP/grimoires/loa/prd.md" --ledger "$BATS_TEST_TMPDIR/none.yaml"
    [ "$status" -eq 1 ]; [[ "$output" == *"ledger unreadable"* ]]
}

@test "validate-artifact prd: a fixture unattended PRD with N [ASSUMPTION decision] tags has N proposed agent rows, each cited" {
    _dec_skip_unless_tools; _dec_project
    _dec_prd "Draft (autonomous run)" 2026-10-13 "placeholder"
    local i ids=() id
    for i in 1 2 3; do
        id="$(bash "$DW" new --file "$DL" --summary "decision $i" --phase discovery --category scope --recorded-by plan-and-analyze \
            --source "grimoires/loa/prd.md#appendix-e (D$i)" --decision "d$i" --rationale "r$i" --alternative-json "$DALT" --answer-ref "session:x#turn-$i" 2>/dev/null)"
        ids+=("$id")
    done
    _dec_prd "Draft (autonomous run)" 2026-10-13 \
        "One. [ASSUMPTION decision] (${ids[0]})" "Two. [ASSUMPTION decision] (${ids[1]})" "Three. [ASSUMPTION decision] (${ids[2]})" "A fact. [ASSUMPTION fact]"
    run "$DV" --type prd --file "$DP/grimoires/loa/prd.md" --json
    [ "$status" -eq 0 ]
    [[ "$(echo "$output" | jq -r '.info[1]')" == "assumption tag classes: fact=1 decision=3 bare=0" ]]
    [ "$(yq -o=json '.' "$DL" | jq '[.decisions[] | select(.status == "proposed" and .proposed_by == "agent" and .decided_by == null and .decided_by_ref == null)] | length')" -eq 3 ]
}

@test "validate-artifact prd: a bare [ASSUMPTION] WARNs before BARE_ASSUMPTION_FAILS_FROM and FAILs from it; tags in code are not counted" {
    _dec_skip_unless_tools; _dec_project
    _dec_prd "Draft" 2026-10-13 "Users have internet. [ASSUMPTION]" 'The tag `[ASSUMPTION decision]` is documented here.'
    run "$DV" --type prd --file "$DP/grimoires/loa/prd.md" --json
    [ "$status" -eq 0 ]
    [[ "$(echo "$output" | jq -r '.warnings | join(" ")')" == *"1 bare [ASSUMPTION] tag(s)"* ]]
    [[ "$(echo "$output" | jq -r '.info[1]')" == "assumption tag classes: fact=0 decision=0 bare=1" ]]
    _dec_prd "Draft" 2026-11-13 "Users have internet. [ASSUMPTION]"
    run "$DV" --type prd --file "$DP/grimoires/loa/prd.md"
    [ "$status" -eq 1 ]; [[ "$output" == *"on or after 2026-11-13"* ]]
}

@test "validate-artifact prd: a **Deferred:** line must cite an existing DEC row" {
    _dec_skip_unless_tools; _dec_project
    _dec_prd "Draft (autonomous run)" 2026-10-13 "**Deferred:** pending prototype bd-abcd (DEC-0001)"
    run "$DV" --type prd --file "$DP/grimoires/loa/prd.md"
    [ "$status" -eq 1 ]; [[ "$output" == *"**Deferred:** line cites no existing DEC row"* ]]
    bash "$DW" new --file "$DL" --summary "look and feel" --phase discovery --category ux --recorded-by t --source "grimoires/loa/prd.md#fr-5" --status open --quiet >/dev/null
    run "$DV" --type prd --file "$DP/grimoires/loa/prd.md"
    [ "$status" -eq 0 ]
}

# ---- sdd: Open Questions DEC column ------------------------------------------------------

@test "validate-artifact sdd: WARNs on a Resolved open question without a DEC id; a cited row does not" {
    {
        sdd_all_sections | sed '/^## 10. Open Questions/,$d'
        printf '## 10. Open Questions\n\n| # | Question | Status | DEC |\n|---|---|---|---|\n| 1 | pacing | Resolved | pending |\n| 2 | ledger | Resolved | DEC-0002 |\n| 3 | later | Open | |\n'
    } > "${TEST_TMPDIR}/sdd.md"
    run "$SCRIPT" --type sdd --file "${TEST_TMPDIR}/sdd.md"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c 'Resolved without a DEC id')" -eq 1 ]
    [[ "$output" == *"sdd.md:23:"* ]]
}

@test "validate-artifact: the PRD and SDD templates carry the decisions appendix rendered by dec-write-lib.sh list" {
    local t
    for t in "$PROJECT_ROOT/.claude/skills/discovering-requirements/resources/templates/prd-template.md" \
             "$PROJECT_ROOT/.claude/skills/designing-architecture/resources/templates/sdd-template.md"; do
        grep -q "Decisions taken on the operator's behalf" "$t"
        grep -q 'dec-write-lib.sh list --not-decided-by operator --cycle {cycle} --format md' "$t"
    done
    grep -q '| Question | Owner | Due Date | Status | DEC |' "$PROJECT_ROOT/.claude/skills/designing-architecture/resources/templates/sdd-template.md"
}

@test "validate-artifact sprint: a task citing a PRD requirement marked **Deferred:** WARNs (never fails)" {
    mkdir -p "${TEST_TMPDIR}/plan"
    printf '# PRD\n\n### FR-5: prototypes\n**Deferred:** pending prototype bd-abcd (DEC-0009)\n\n### FR-6: glossary\nnot deferred\n' > "${TEST_TMPDIR}/plan/prd.md"
    {
        printf '## Sprint 1: x\n\n### Sprint Goal\ng\n### Deliverables\nd\n### Acceptance Criteria\na\n### Technical Tasks\n'
        printf -- '- [ ] Task 1.1: build FR-5 spike UI\n- [ ] Task 1.2: FR-6 glossary\n- [ ] Task 1.3: E2E\n'
        printf '### Dependencies\nn\n### Risks & Mitigation\nr\n### Security Considerations\ns\n### Success Metrics\nm\n'
    } > "${TEST_TMPDIR}/plan/sprint.md"
    run "$SCRIPT" --type sprint --file "${TEST_TMPDIR}/plan/sprint.md"
    [ "$status" -eq 0 ]
    [ "$(printf '%s\n' "$output" | grep -c 'which the PRD marks \*\*Deferred:\*\*')" -eq 1 ]
    [[ "$output" == *"sprint.md:10: this task cites FR-5"* ]]
}

# =============================================================================
# map (grimoires/loa/sdd.md D-4.8, §4.2)
# =============================================================================

# A map doc in the §4.2 shape; outside the project, so the beads check is a WARN.
map_fixture() {
    cat <<'MAP'
# Map: Ceiling arc

**Slug**: ceiling-arc
**Status**: charting
**Epic**: bd-map1
**Created**: 2026-10-14

## Destination
The Opus ceiling is measured on every transport.

## Decisions so far
- Transport (DEC-0001, bd-c1): headless first

## Not yet specified
- retry budget

## Out of scope
- pricing: another cycle
MAP
}

@test "validate-artifact map: a valid map doc passes (beads check skipped with one WARN outside the project)" {
    map_fixture > "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: beads cross-check skipped"* ]]
}

@test "validate-artifact map: a final ## Closed section passes; any section after it fails" {
    { map_fixture; printf '\n## Closed\n2026-10-20, consumed by cycle-129\n'; } > "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 0 ]
    printf '\n## Out of scope\n- again\n' >> "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"after '## Closed'"* ]]
}

@test "validate-artifact map: an extra H2 fails (no execution override)" {
    { map_fixture; printf '\n## Execution override\nImplement it now under src/.\n'; } > "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'## Execution override' is not a map section"* ]]
    [[ "$output" == *"carries no execution instructions"* ]]
}

@test "validate-artifact map: an H2 inside a fenced code block is not a section" {
    { map_fixture; printf '\n```\n## Not a heading\n```\n'; } > "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 0 ]
}

@test "validate-artifact map: a Decisions so far bullet without a DEC id fails" {
    map_fixture | sed 's/(DEC-0001, bd-c1)/(bd-c1)/' > "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bullet cites no DEC row"* ]]
}

@test "validate-artifact map: sections out of order, a missing section and a second H1 each fail" {
    map_fixture | awk '/^## Not yet specified/{skip=1} /^## Out of scope/{skip=0} !skip' > "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"missing section '## Not yet specified'"* ]]
    { map_fixture | sed 's/^## Destination$/## Decisions so far/; 0,/^## Decisions so far$/!{s/^## Decisions so far$/## Destination/}'; } > "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"out of order or repeated"* ]]
    { map_fixture; printf '\n# Plan\n'; } > "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"exactly one H1"* ]]
}

@test "validate-artifact map: a bad Status, a missing Slug or Epic, and an empty Destination fail" {
    map_fixture | sed 's/^\*\*Status\*\*: charting/**Status**: building/' > "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"**Status** 'building' is not one of"* ]]
    map_fixture | grep -vE '^\*\*(Slug|Epic)\*\*:' > "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no '**Slug**:' header"* ]]
    [[ "$output" == *"no '**Epic**:' header"* ]]
    map_fixture | grep -v '^The Opus ceiling' > "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'## Destination' is empty"* ]]
}

@test "validate-artifact map: every documented Status value passes" {
    local st
    for st in charting handed-off closed abandoned; do
        map_fixture | sed "s/^\*\*Status\*\*: charting/**Status**: $st/" > "${TEST_TMPDIR}/map.md"
        run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
        [ "$status" -eq 0 ]
    done
}

@test "validate-artifact map: a URL and a three-line blockquote fail (plain prose)" {
    { map_fixture; printf -- '- see https://example.invalid/x\n'; } > "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"a URL in the document"* ]]
    { map_fixture; printf '\n> one\n> two\n> three\n'; } > "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"a blockquote of 3 lines"* ]]
    { map_fixture; printf '\n> one\n> two\n'; } > "${TEST_TMPDIR}/map.md"
    run "$SCRIPT" --type map --file "${TEST_TMPDIR}/map.md"
    [ "$status" -eq 0 ]
}

# ---- Bridgebuilder round: merge-base history mode (F-002), jq floor (F-012), PROJECT_ROOT (F-017) ----

# A git repo whose origin/main holds the ledger with one open row; the working copy then moves on.
_dec_mergebase_project() {
    _dec_project
    bash "$DW" new --file "$DL" --summary "an open question" --phase discovery --category scope --recorded-by t --source "prd.md#q" --status open --quiet >/dev/null
    git -C "$DP" add -A
    git -C "$DP" -c core.hooksPath=/dev/null -c user.email=t@t -c user.name=t commit -qm base
    git -C "$DP" update-ref refs/remotes/origin/main HEAD
    git -C "$DP" show HEAD:grimoires/loa/decisions.yaml > "$BATS_TEST_TMPDIR/mb-base.yaml"
}

@test "validate-artifact decisions F-002: a branch row open -> proposed -> decided validates against its merge-base copy (history rules)" {
    _dec_skip_unless_tools; _dec_mergebase_project
    bash "$DW" decide --file "$DL" --id DEC-0001 --decision d --rationale r --alternative-json "$DALT" --evidence e --recorded-by t --quiet
    _dec_confirm DEC-0001
    [ "$(yq '.decisions[0].transitions | length' "$DL")" -eq 3 ]
    run "$DV" --type decisions --file "$DL"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"append-only base: grimoires/loa/decisions.yaml at merge-base"* ]]
    # the writer's single-write path (--base-file) keeps the strict rule
    run "$DV" --type decisions --file "$DL" --base-file "$BATS_TEST_TMPDIR/mb-base.yaml"
    [ "$status" -eq 1 ]; [[ "$output" == *"more than one transition appended in one write"* ]]
}

@test "validate-artifact decisions F-002: in merge-base mode an edited base-prefix transition and an unlegitimised content edit still fail" {
    _dec_skip_unless_tools; _dec_mergebase_project
    bash "$DW" decide --file "$DL" --id DEC-0001 --decision d --rationale r --alternative-json "$DALT" --evidence e --recorded-by t --quiet
    _dec_confirm DEC-0001
    cp "$DL" "$BATS_TEST_TMPDIR/good.yaml"
    yq -i '.decisions[0].transitions[0].evidence = "rewritten"' "$DL"
    run "$DV" --type decisions --file "$DL"
    [ "$status" -eq 1 ]; [[ "$output" == *"DEC-0001: transitions rewritten (append only)"* ]]
    cp "$BATS_TEST_TMPDIR/good.yaml" "$DL"
    # no appended transition reaches rejected, so nothing legitimises a rejection_rationale
    yq -i '.decisions[0].rejection_rationale = "slipped in"' "$DL"
    run "$DV" --type decisions --file "$DL"
    [ "$status" -eq 1 ]; [[ "$output" == *"DEC-0001: content edit to rejection_rationale"* ]]
    cp "$BATS_TEST_TMPDIR/good.yaml" "$DL"
    yq -i '.decisions[0].summary = "rewritten"' "$DL"
    run "$DV" --type decisions --file "$DL"
    [ "$status" -eq 1 ]; [[ "$output" == *"DEC-0001: content edit to summary"* ]]
}

@test "validate-artifact decisions F-012: validate_decisions uses no jq IN() (absent from jq 1.5)" {
    run bash -c 'awk "/^validate_decisions\\(\\) \\{/,/^}/" "$1" | grep -c "IN("' _ "$SCRIPT"
    [ "$output" = "0" ]
    # and the function still evaluates (a writer-built ledger with every status passes)
    _dec_skip_unless_tools; _dec_project
    _dec_new_prop >/dev/null; _dec_new_prop >/dev/null; _dec_confirm DEC-0001
    bash "$DW" reject --file "$DL" --id DEC-0002 --rationale no --follow-up bd-x --recorded-by t --quiet
    run "$DV" --type decisions --file "$DL"
    [ "$status" -eq 0 ]
}

@test "validate-artifact decisions F-017: the context probe reads the validator's PROJECT_ROOT, not the script's tree" {
    _dec_skip_unless_tools; _dec_project
    _dec_new_prop >/dev/null
    cp "$DL" "$BATS_TEST_TMPDIR/base.yaml"
    _dec_confirm DEC-0001
    # the repository's own validator, pointed at the fixture tree whose run state is RUNNING
    mkdir -p "$DP/.run"; printf '{"state":"RUNNING"}\n' > "$DP/.run/state.json"
    run env PROJECT_ROOT="$DP" "$SCRIPT" --type decisions --file "$DL" --base-file "$BATS_TEST_TMPDIR/base.yaml"
    [ "$status" -eq 1 ]; [[ "$output" == *"decided_by operator written while a live unattended signal holds"* ]]
    rm -f "$DP/.run/state.json"
    run env PROJECT_ROOT="$DP" "$SCRIPT" --type decisions --file "$DL" --base-file "$BATS_TEST_TMPDIR/base.yaml"
    [ "$status" -eq 0 ]
}

@test "validate-artifact prd F-003: an autonomous PRD Status line still makes the PRD gate fail an uncited [ASSUMPTION decision]" {
    _dec_skip_unless_tools; _dec_project
    _dec_prd "Draft (autonomous run)" 2026-10-13 "We take rounds. [ASSUMPTION decision] (DEC-0001)"
    run "$DV" --type prd --file "$DP/grimoires/loa/prd.md"
    [ "$status" -eq 1 ]; [[ "$output" == *"(unattended PRD)"* ]]
}

@test "validate-artifact sdd F-007: an Open Questions row marked Unresolved is not read as Resolved; a Resolved row without a DEC id still WARNs" {
    local f="${TEST_TMPDIR}/sdd-oq.md"
    cat > "$f" <<'SDD'
# SDD: fixture

## 1. Overview
Text.

## 10. Open Questions

| # | Question | Status | Resolved by | DEC |
|---|----------|--------|-------------|-----|
| 1 | Pending one | Unresolved | — | — |
| 2 | Settled one | Resolved | D-1.1 | — |
| 3 | Cited one | Resolved | D-1.2 | DEC-0001 |

## 11. Appendix
Text.
SDD
    run "$SCRIPT" --type sdd --file "$f"
    [ "$(grep -c 'an Open Questions row is Resolved without a DEC id' <<< "$output")" -eq 1 ]
    [[ "$output" == *":11:"* ]]
    [[ "$output" != *":10:"* ]]
}
