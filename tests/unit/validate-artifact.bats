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
