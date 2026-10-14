#!/usr/bin/env bats
# =============================================================================
# tests/unit/spike-validator.bats: the spike discipline (grimoires/loa/sdd.md
# D-5.4, D-5.5, D-5.9).
#
#   validate-artifact.sh --type spike: the template passes; an empty Verdict,
#   a missing section, a Pointer without a branch or path, a Decided by naming
#   neither operator nor agent, a non-spike Branch header and a URL fail.
#   block-destructive-bash.sh: SP-1 cases that need a git checkout (gh pr
#   create with no head on a spike branch), and the spike-delete predicate:
#   force-deleting spike/<slug> passes only with a decided verdict row.
# The command-string shapes of SP-1 live in the fence corpus
# (tests/fixtures/fence-corpus/corpus.jsonl, rows B50-B59 and D61-D72).
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    VALIDATE="$PROJECT_ROOT/.claude/scripts/validate-artifact.sh"
    TEMPLATE="$PROJECT_ROOT/grimoires/loa/spikes/TEMPLATE.md"
    HOOK="$PROJECT_ROOT/.claude/hooks/safety/block-destructive-bash.sh"
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    WORK="$(mktemp -d)"
    export LOA_REPO_ROOT="$WORK/audit"
    mkdir -p "$LOA_REPO_ROOT"
}

teardown() {
    cd /
    rm -rf "$WORK"
}

# A filled-in report.
spike_report() {
    cat <<'EOF'
# Spike: ceiling-ui

**Bead**: bd-p1
**Branch**: spike/ceiling-ui
**Date**: 2026-10-14

## Question
Does the ceiling table read better as a chart?

## What was built
A static page rendering both forms from one fixture.

## Verdict
The chart, with the table behind a toggle.

## Pointer
Branch spike/ceiling-ui at commit 1a2b3c4.

## Decided by
operator, recorded as DEC-0042.
EOF
}

# Replace the body of section $1 in stdin with $2 (empty: drop the body).
with_section() {
    awk -v want="## $1" -v repl="$2" '
        $0 == want { print; if (repl != "") print repl; skip = 1; next }
        skip && /^## / { skip = 0 }
        !skip { print }
    '
}

hook_in() {
    local dir="$1" cmd="$2"
    (cd "$dir" && jq -cn --arg c "$cmd" '{tool_input: {command: $c}}' | bash "$HOOK")
}

# --- validate-artifact.sh --type spike ------------------------------------------

@test "spike: the shipped template passes" {
    run "$VALIDATE" --type spike --file "$TEMPLATE"
    [ "$status" -eq 0 ]
}

@test "spike: a filled-in report passes without warnings" {
    spike_report > "$WORK/r.md"
    run "$VALIDATE" --type spike --file "$WORK/r.md"
    [ "$status" -eq 0 ]
    [[ "$output" != *"WARN"* ]]
}

@test "spike: an empty Verdict fails (template and report)" {
    with_section "Verdict" "" < "$TEMPLATE" > "$WORK/t.md"
    run "$VALIDATE" --type spike --file "$WORK/t.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'## Verdict' is empty"* ]]
    spike_report | with_section "Verdict" "" > "$WORK/r.md"
    run "$VALIDATE" --type spike --file "$WORK/r.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'## Verdict' is empty"* ]]
}

@test "spike: each missing section is named" {
    local s
    for s in "Question" "What was built" "Verdict" "Pointer" "Decided by"; do
        spike_report | grep -vxF "## $s" > "$WORK/r.md"
        run "$VALIDATE" --type spike --file "$WORK/r.md"
        [ "$status" -eq 1 ]
        [[ "$output" == *"missing section '## $s'"* ]]
    done
}

@test "spike: a Pointer naming neither a spike branch nor a path fails; a path passes" {
    spike_report | with_section "Pointer" "the prototype we looked at" > "$WORK/r.md"
    run "$VALIDATE" --type spike --file "$WORK/r.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"'## Pointer' names neither"* ]]
    spike_report | with_section "Pointer" "prototypes/ceiling/index.html" > "$WORK/r.md"
    run "$VALIDATE" --type spike --file "$WORK/r.md"
    [ "$status" -eq 0 ]
}

@test "spike: Decided by must name operator or agent; a missing DEC id WARNs" {
    spike_report | with_section "Decided by" "the team, DEC-0042" > "$WORK/r.md"
    run "$VALIDATE" --type spike --file "$WORK/r.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"names neither operator nor agent"* ]]
    spike_report | with_section "Decided by" "agent" > "$WORK/r.md"
    run "$VALIDATE" --type spike --file "$WORK/r.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: '## Decided by' cites no DEC row"* ]]
}

@test "spike: a Branch header that is not spike/<slug> fails; a multi-line Verdict WARNs" {
    spike_report | sed 's#^\*\*Branch\*\*: spike/ceiling-ui#**Branch**: feature/ceiling-ui#' > "$WORK/r.md"
    run "$VALIDATE" --type spike --file "$WORK/r.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not a spike/<slug> branch"* ]]
    spike_report | with_section "Verdict" $'The chart.\nAlso the table.' > "$WORK/r.md"
    run "$VALIDATE" --type spike --file "$WORK/r.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: '## Verdict' has 2 lines"* ]]
}

@test "spike: a URL fails (plain prose)" {
    spike_report | with_section "Pointer" "spike/ceiling-ui, demo at https://example.invalid/demo" > "$WORK/r.md"
    run "$VALIDATE" --type spike --file "$WORK/r.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"a URL in the document"* ]]
}

@test "spike: a report validated on a spike checkout WARNs that it belongs on the working branch" {
    git init -q "$WORK/repo"
    git -C "$WORK/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    git -C "$WORK/repo" checkout -q -b spike/ceiling-ui
    spike_report > "$WORK/repo/r.md"
    run "$VALIDATE" --type spike --file "$WORK/repo/r.md"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: this checkout is on spike/ceiling-ui"* ]]
}

# --- SP-1 cases that need a git checkout ------------------------------------------

spike_repo() {
    REPO="$WORK/repo"
    git init -q "$REPO"
    git -C "$REPO" config user.email t@t
    git -C "$REPO" config user.name t
    git -C "$REPO" commit -q --allow-empty -m init
    BASE="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
    git -C "$REPO" checkout -q -b spike/ceiling-ui
    git -C "$REPO" commit -q --allow-empty -m "prototype"
    git -C "$REPO" checkout -q "$BASE"
}

@test "SP-1: gh pr create with no head is blocked on a spike branch and allowed on the working branch" {
    spike_repo
    run hook_in "$REPO" "gh pr create --draft --title t --body b"
    [ "$status" -eq 0 ]
    git -C "$REPO" checkout -q spike/ceiling-ui
    run hook_in "$REPO" "gh pr create --draft --title t --body b"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCKED [SP-1]"* ]]
    # an explicit non-spike head is the operator's statement: not judged by branch
    run hook_in "$REPO" "gh pr create --draft --head feature/x --title t --body b"
    [ "$status" -eq 0 ]
}

@test "SP-1: the block message names the allowed forms and the working-branch rule" {
    run hook_in "$WORK" "git merge spike/ceiling-ui"
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCKED [SP-1]"* ]]
    [[ "$output" == *"git push -u origin spike/<slug>"* ]]
    [[ "$output" == *"on the working branch"* ]]
}

# --- the spike-delete predicate (D-5.9) -------------------------------------------

skip_without_yq4() {
    command -v yq >/dev/null 2>&1 || skip "yq not installed"
    yq --version 2>&1 | grep -q 'mikefarah.*version v4\.' || skip "needs mikefarah yq v4"
}

# write_ledger <status> <source> <by-of-the-decided-step>
write_ledger() {
    mkdir -p "$REPO/grimoires/loa"
    cat > "$REPO/grimoires/loa/decisions.yaml" <<EOF
schema_version: 1
decisions:
  - id: "DEC-0042"
    status: "$1"
    source: "$2"
    transitions:
      - {at: "2026-10-14T00:00:00Z", from: null, to: open, by: "agent:chart"}
      - {at: "2026-10-14T01:00:00Z", from: open, to: proposed, by: "agent:chart"}
      - {at: "2026-10-14T02:00:00Z", from: proposed, to: decided, by: "$3"}
EOF
}

force_delete() {
    run hook_in "$REPO" "git branch -D $*"
}

@test "D-5.9: force-deleting an unmerged spike branch is blocked without a ledger row" {
    spike_repo
    force_delete spike/ceiling-ui
    [ "$status" -eq 2 ]
    [[ "$output" == *"BLOCKED [FR-1.1]"* ]]
    [[ "$output" == *"whose verdict row"* ]]
}

@test "D-5.9: a decided verdict row (operator step) for the spike's report allows the delete" {
    skip_without_yq4
    spike_repo
    write_ledger decided "grimoires/loa/spikes/ceiling-ui.md" "operator:decisions-command"
    force_delete spike/ceiling-ui
    [ "$status" -eq 0 ]
    write_ledger decided "grimoires/loa/spikes/ceiling-ui.md#verdict" "operator:decisions-command"
    force_delete spike/ceiling-ui
    [ "$status" -eq 0 ]
}

@test "D-5.9: a proposed row, an agent decided step, or another spike's row keeps the block" {
    skip_without_yq4
    spike_repo
    write_ledger proposed "grimoires/loa/spikes/ceiling-ui.md" "operator:decisions-command"
    force_delete spike/ceiling-ui
    [ "$status" -eq 2 ]
    write_ledger decided "grimoires/loa/spikes/ceiling-ui.md" "agent:chart"
    force_delete spike/ceiling-ui
    [ "$status" -eq 2 ]
    write_ledger decided "grimoires/loa/spikes/other.md" "operator:decisions-command"
    force_delete spike/ceiling-ui
    [ "$status" -eq 2 ]
}

@test "D-5.9: every name must qualify; an unmerged non-spike branch beside a decided spike keeps the block" {
    skip_without_yq4
    spike_repo
    git -C "$REPO" checkout -q -b feature/wip
    git -C "$REPO" commit -q --allow-empty -m wip
    git -C "$REPO" checkout -q "$BASE"
    write_ledger decided "grimoires/loa/spikes/ceiling-ui.md" "operator:decisions-command"
    force_delete spike/ceiling-ui feature/wip
    [ "$status" -eq 2 ]
}

@test "D-5.9: an unparsable ledger keeps the block" {
    skip_without_yq4
    spike_repo
    mkdir -p "$REPO/grimoires/loa"
    printf 'decisions: [unclosed\n' > "$REPO/grimoires/loa/decisions.yaml"
    force_delete spike/ceiling-ui
    [ "$status" -eq 2 ]
}
