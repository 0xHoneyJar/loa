#!/usr/bin/env bats
# validate-artifact.sh --type sprint: every task line ends with exactly one
# 'kind: mechanical|judgment|operator' token, gated on the plan's header **Date:**
# (grimoires/loa/sdd.md D-10.1; KINDS_REQUIRED_FROM=2026-10-14; DEC-0144, DEC-0154).

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    SCRIPT="${PROJECT_ROOT}/.claude/scripts/validate-artifact.sh"
    T="${BATS_TEST_TMPDIR}"
}

# One sprint block; $1 = the Technical Tasks lines (printf-ready, one per line).
sprint_body() {
    printf '### Sprint Goal\ng\n\n### Deliverables\n- [ ] d\n\n### Acceptance Criteria\n- [ ] c\n\n'
    printf '### Technical Tasks\n%s\n\n' "$1"
    printf '### Seams Under Test\n| Seam | Catches | Misses | Prior art |\n|------|---------|--------|-----------|\n| `tool.sh` exit code | a wrong exit | prose | new |\n\n'
    printf '### Dependencies\n- none\n\n### Security Considerations\n- none\n\n'
    printf '### Risks & Mitigation\n| Risk | Probability | Impact | Mitigation |\n|---|---|---|---|\n| r | Low | Low | m |\n\n'
    printf '### Success Metrics\n- m\n\n'
}
# $1 = header date (may be empty); $2 = sprint 1 task lines; $3 = the E2E task line.
plan() {
    printf '# Sprint Plan: x\n\n**Version:** 1.0\n'
    [[ -n "$1" ]] && printf '**Date:** %s\n' "$1"
    printf '**Author:** test\n\n---\n\n'
    printf '## Sprint 1: Foundation\n\n'; sprint_body "$2"
    printf '## Sprint 2 (Final): Wrap-up\n\n'
    sprint_body '- [ ] Task 2.1: wire the thing → **[G-1]** ⇐ Task 1.1 · kind: mechanical'
    printf '### Task 2.E2E: End-to-End Goal Validation\n%s\n\n' "$3"
    printf '**Acceptance Criteria:**\n- [ ] Each goal validated with documented evidence\n\n'
    printf '## Appendix\n\n| Goal ID | Goal |\n|---|---|\n| G-1 | thing |\n'
}
TAGGED='- [ ] Task 1.1: add the tool → **[G-1]** ⇐ none · kind: mechanical'
E2E='- [ ] Task 2.E2E: validate every goal → **[G-1]** ⇐ Task 2.1 · kind: judgment'

@test "KINDS-1 a plan dated 2026-10-14 with an untagged task fails and names the line" {
    plan 2026-10-14 '- [ ] Task 1.1: add the tool → **[G-1]** ⇐ none' "$E2E" > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    [[ "$output" == *"sprint.md:"*": a task line has no kind: token"*"on or after 2026-10-14"* ]]
    [ "$(grep -c 'kind: token' <<< "$output")" -eq 1 ]
}

@test "KINDS-2 the same plan with every task tagged passes without a kind message" {
    plan 2026-10-14 "$TAGGED" "$E2E" > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" != *"kind:"* ]]
}

@test "KINDS-3 a plan dated before 2026-10-14 with untagged tasks passes with one WARN" {
    plan 2026-10-13 '- [ ] Task 1.1: add the tool → **[G-1]** ⇐ none' \
        '- [ ] Task 2.E2E: validate every goal → **[G-1]**' > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"WARN: 2026-10-13 plan: 2 task line(s) without a valid kind: tag; the tag is required for plans dated from 2026-10-14"* ]]
    [ "$(grep -c 'kind:' <<< "$output")" -eq 1 ]
}

@test "KINDS-4 two kind: tokens on one task line fail" {
    plan 2026-10-14 '- [ ] Task 1.1: add the tool kind: judgment → **[G-1]** · kind: mechanical' "$E2E" > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    [[ "$output" == *"carries 2 kind: tokens; keep exactly one"* ]]
}

@test "KINDS-5 trailing prose after the value fails; an unknown value fails" {
    plan 2026-10-14 '- [ ] Task 1.1: add the tool → **[G-1]** · kind: mechanical (see notes)' "$E2E" > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    [[ "$output" == *"has text after its kind: value"* ]]
    plan 2026-10-14 '- [ ] Task 1.1: add the tool → **[G-1]** · kind: manual' "$E2E" > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    [[ "$output" == *"is not one of mechanical, judgment, operator"* ]]
}

@test "KINDS-6 a live plan with no parseable header date fails; the same plan archived WARNs" {
    local root="$T/proj"
    mkdir -p "$root/grimoires/loa/archive/cycle-x"
    plan "" '- [ ] Task 1.1: add the tool → **[G-1]** ⇐ none' "$E2E" > "$root/grimoires/loa/sprint.md"
    run env PROJECT_ROOT="$root" "$SCRIPT" --type sprint --file "$root/grimoires/loa/sprint.md"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    [[ "$output" == *"so the kind: rule (from 2026-10-14) cannot be judged"* ]]
    cp "$root/grimoires/loa/sprint.md" "$root/grimoires/loa/archive/cycle-x/sprint.md"
    run env PROJECT_ROOT="$root" "$SCRIPT" --type sprint --file "$root/grimoires/loa/archive/cycle-x/sprint.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"WARN: undated plan: 1 task line(s) without a valid kind: tag"* ]]
}

@test "KINDS-7 a judgment task naming only script files or a script verb WARNs and still passes" {
    plan 2026-10-14 '- [ ] Task 1.1: write `tools/foo.sh` and `lib/bar.py` → **[G-1]** ⇐ none · kind: judgment
- [ ] Task 1.2: lint the plans → **[G-1]** · kind: judgment
- [ ] Task 1.3: decide the wording in `README.md` and `tools/foo.sh` → **[G-1]** · kind: judgment
- [ ] Task 1.4: write `tools/baz.ts` → **[G-1]** · kind: mechanical' "$E2E" > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [ "$(grep -c 'a task tagged kind: judgment names only' <<< "$output")" -eq 2 ]
    local l1 l2
    l1="$(grep -n 'Task 1.1:' "$T/sprint.md" | cut -d: -f1)"
    l2="$(grep -n 'Task 1.2:' "$T/sprint.md" | cut -d: -f1)"
    [[ "$output" == *"sprint.md:${l1}: a task tagged kind: judgment"* ]]
    [[ "$output" == *"sprint.md:${l2}: a task tagged kind: judgment"* ]]
}

@test "KINDS-8 the E2E task is covered; its acceptance checkboxes, inline code, fences and spacing are not tokens" {
    # the E2E task line untagged on a dated plan fails
    plan 2026-10-14 "$TAGGED" '- [ ] Task 2.E2E: validate every goal → **[G-1]**' > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
    local le; le="$(grep -n 'Task 2.E2E: validate' "$T/sprint.md" | cut -d: -f1)"
    [[ "$output" == *"sprint.md:${le}: a task line has no kind: token"* ]]
    # a backticked `kind:` in the prose is not a second token; spacing around the colon
    # is tolerated; the dependency marker may be absent; a fenced checkbox is not a task
    plan 2026-10-14 '- [ ] Task 1.1: add the `kind:` rule → **[G-1]** ·   kind :  operator
- [x] Task 1.2: done already · kind:mechanical
```
- [ ] not a task
```' "$E2E" > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" != *"kind:"* ]]
    # a backticked token is not the tag
    plan 2026-10-14 '- [ ] Task 1.1: add the tool → **[G-1]** `kind: mechanical`' "$E2E" > "$T/sprint.md"
    run "$SCRIPT" --type sprint --file "$T/sprint.md"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}

@test "KINDS-9 this cycle's grimoires/loa/sprint.md passes" {
    [ -f "$PROJECT_ROOT/grimoires/loa/sprint.md" ] || skip "no live sprint plan in this checkout"
    grep -q '^\*\*Date:\*\* 2026-1[0-2]-' "$PROJECT_ROOT/grimoires/loa/sprint.md" || skip "the live plan predates the kind: rule"
    run "$SCRIPT" --type sprint --file "$PROJECT_ROOT/grimoires/loa/sprint.md"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" != *"without a valid kind: tag"* ]]
}

@test "KINDS-10 the archived cycle-128 plan (dated 2026-10-13) gains only a WARN from the rule" {
    local f="$PROJECT_ROOT/tests/fixtures/sprint-kinds/cycle-128-sprint.md"
    run "$SCRIPT" --type sprint --file "$f"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"WARN: 2026-10-13 plan: "*" task line(s) without a valid kind: tag"* ]]
}

@test "KINDS-11 the shipped sprint template ends its task lines with the kind: token" {
    local t="$PROJECT_ROOT/.claude/skills/planning-sprints/resources/templates/sprint-template.md"
    [ "$(grep -cE '^- \[ \] .*· kind: [a-z{]' "$t")" -ge 3 ]
    grep -q 'mechanical' "$t"
    grep -q 'operator' "$t"
}
