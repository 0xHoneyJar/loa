#!/usr/bin/env bats
# validate-artifact.sh --type sprint: the '### Seams Under Test' rule gated on the plan's
# header **Date:** (grimoires/loa/sdd.md D-7.2; SEAMS_REQUIRED_FROM=2026-10-13).

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PROJECT_ROOT}/.claude/scripts/validate-artifact.sh"
    T="${BATS_TEST_TMPDIR}"
}

# A plan with two sprint blocks; $1 = header date line (may be empty), $2 = seams in sprint 1
# (yes|no|empty), $3 = seams in sprint 2 (yes|no|empty).
seams_block() {
    case "$1" in
        yes) printf '### Seams Under Test\n| Seam | Catches | Misses | Prior art |\n|------|---------|--------|-----------|\n| `tool.sh` exit code | a wrong exit | prose | new |\n\n' ;;
        empty) printf '### Seams Under Test\n| Seam | Catches | Misses | Prior art |\n|------|---------|--------|-----------|\n\n' ;;
        *) ;;
    esac
}
sprint_body() {
    printf '### Sprint Goal\ng\n\n### Deliverables\n- [ ] d\n\n### Acceptance Criteria\n- [ ] c\n\n'
    printf '### Technical Tasks\n- [ ] Task %s → **[G-1]** · kind: mechanical\n\n' "$2"
    seams_block "$1"
    printf '### Dependencies\n- none\n\n### Security Considerations\n- none\n\n'
    printf '### Risks & Mitigation\n| Risk | Probability | Impact | Mitigation |\n|---|---|---|---|\n| r | Low | Low | m |\n\n'
    printf '### Success Metrics\n- m\n\n'
}
plan() {
    printf '# Sprint Plan: x\n\n**Version:** 1.0\n'
    [[ -n "$1" ]] && printf '**Date:** %s\n' "$1"
    printf '**Author:** test\n\n---\n\n'
    printf '## Sprint 1: Foundation\n\n'; sprint_body "$2" "1.1"
    printf '## Sprint 2 (Final): Wrap-up\n\n'; sprint_body "$3" "2.E2E: End-to-End Goal Validation"
    printf '## Appendix\n\n| Goal ID | Goal |\n|---|---|\n| G-1 | thing |\n'
}

@test "SEAMS-1 a plan dated 2026-10-13 without the block fails and names each sprint missing it" {
    plan 2026-10-13 yes no > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Sprint 2 (Final): Wrap-up (line"*"has no '### Seams Under Test' table"* ]]
    [[ "$output" != *"Sprint 1: Foundation (line"*"Seams Under Test"* ]]
}

@test "SEAMS-2 the same plan with the block in every sprint passes without a seams WARN" {
    plan 2026-10-13 yes yes > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" != *"Seams Under Test"* ]]
}

@test "SEAMS-3 a later date also requires it; a heading with no table row counts as missing" {
    plan 2026-11-02 empty yes > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Sprint 1: Foundation (line"*"has no '### Seams Under Test' table with at least one row"* ]]
}

@test "SEAMS-4 a plan dated 2026-10-12 without the block passes with one WARN" {
    plan 2026-10-12 no no > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"WARN: 2026-10-12 plan: 2 sprint block(s) without a '### Seams Under Test' table"* ]]
    [ "$(grep -c 'Seams Under Test' <<< "$output")" -eq 1 ]
}

@test "SEAMS-5 an undated plan passes with one WARN" {
    plan "" no no > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"WARN: undated plan: 2 sprint block(s)"* ]]
}

@test "SEAMS-6 a Date line below the first H2 is not the header date (the plan reads as undated)" {
    { plan "" no no; printf '\n## Notes\n\n**Date:** 2026-12-01\n'; } > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"WARN: undated plan"* ]]
}

@test "SEAMS-7 a Seams heading inside fenced code does not count; a block under a later H2 does not either" {
    {
        plan 2026-10-13 yes no | sed '/^## Appendix/,$d'
        printf '```\n### Seams Under Test\n| Seam | Catches | Misses | Prior art |\n|---|---|---|---|\n| a | b | c | d |\n```\n\n'
        printf '## Risk Register\n\n### Seams Under Test\n| Seam | Catches | Misses | Prior art |\n|---|---|---|---|\n| a | b | c | d |\n\n'
        printf '## Appendix\n\n| Goal ID | Goal |\n|---|---|\n| G-1 | thing |\n'
    } > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Sprint 2 (Final): Wrap-up (line"*"Seams Under Test"* ]]
}

@test "SEAMS-8 this cycle's grimoires/loa/sprint.md passes" {
    [ -f "$PROJECT_ROOT/grimoires/loa/sprint.md" ] || skip "no live sprint plan in this checkout"
    grep -q '^\*\*Date:\*\* 2026-10-1[3-9]' "$PROJECT_ROOT/grimoires/loa/sprint.md" || skip "the live plan is not the cycle-128 plan"
    run "$SCRIPT" --type sprint --file "$PROJECT_ROOT/grimoires/loa/sprint.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" != *"Seams Under Test"* ]]
}

@test "SEAMS-9 the archived cycle-127 plan (dated 2026-10-07) gains only a WARN from the rule" {
    local f="$PROJECT_ROOT/tests/fixtures/sprint-seams/cycle-127-sprint.md"
    run "$SCRIPT" --type sprint --file "$f"
    [[ "$output" == *"WARN: 2026-10-07 plan: 1 sprint block(s) without a '### Seams Under Test' table"* ]]
    [[ "$output" != *"has no '### Seams Under Test' table with"* ]]
    # The plan predates the template's Risks & Mitigation / Success Metrics sections and fails
    # on those alone, exactly as it did before the seams rule; the rule adds no violation.
    local others
    others="$(grep -v '^WARN\|^INFO' <<< "$output" | grep -vc "missing required section '### \(Risks & Mitigation\|Success Metrics\)'" || true)"
    [ "$others" -eq 0 ]
}

@test "SEAMS-10 the shipped sprint template carries the block in each full sprint block" {
    local t="$PROJECT_ROOT/.claude/skills/planning-sprints/resources/templates/sprint-template.md"
    [ "$(grep -c '^### Seams Under Test$' "$t")" -eq 2 ]
    [ "$(grep -c '^| Seam | Catches | Misses | Prior art |$' "$t")" -eq 2 ]
}

@test "SEAMS-11 a four-backtick fence holding a three-backtick line no longer hides the next sprint block" {
    plan 2026-10-13 yes no | awk '/^## Sprint 2/ { print "````"; print "```"; print "````"; print "" } { print }' > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    [[ "$output" == *"Sprint 2 (Final): Wrap-up (line"*"has no '### Seams Under Test' table"* ]]
}

@test "SEAMS-12 a live plan under grimoires/loa/ without a parseable header Date fails; the archive keeps the WARN" {
    local root="$T/proj"
    mkdir -p "$root/grimoires/loa/archive/cycle-x"
    plan "" yes yes > "$root/grimoires/loa/sprint.md"
    run env PROJECT_ROOT="$root" "$SCRIPT" --type sprint --file "$root/grimoires/loa/sprint.md"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    [[ "$output" == *"a sprint plan carries **Date:** YYYY-MM-DD in its header"* ]]
    # an unparseable date is the same failure
    plan "" yes yes | sed 's/^\*\*Author:\*\*/**Date:** October 13, 2026\n**Author:**/' > "$root/grimoires/loa/sprint.md"
    grep -q '^\*\*Date:\*\* October' "$root/grimoires/loa/sprint.md"
    run env PROJECT_ROOT="$root" "$SCRIPT" --type sprint --file "$root/grimoires/loa/sprint.md"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    # the same undated plan in the archive, or outside the project, passes with the WARN
    plan "" no no > "$root/grimoires/loa/archive/cycle-x/sprint.md"
    run env PROJECT_ROOT="$root" "$SCRIPT" --type sprint --file "$root/grimoires/loa/archive/cycle-x/sprint.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"WARN: undated plan: 2 sprint block(s)"* ]]
    # a dated live plan with its blocks passes
    plan 2026-10-14 yes yes > "$root/grimoires/loa/sprint.md"
    run env PROJECT_ROOT="$root" "$SCRIPT" --type sprint --file "$root/grimoires/loa/sprint.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
