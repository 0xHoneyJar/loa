#!/usr/bin/env bats
# =============================================================================
# tests/unit/lint-invariants.bats — cycle-129 D-4.5 (AC-2.5)
#
# The five C-TEAM rows left constraints.json; generate-constraints.sh omits the
# "## Agent Teams" table when the class is empty and renders it when rows
# exist; lint-invariants.sh fails when the kernel and the registry disagree.
# The generator runs against a fixture tree (it resolves its inputs relative
# to the working directory), never against the live kernel.
# =============================================================================

setup() {
    R="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    GEN="$R/.claude/scripts/generate-constraints.sh"
    LINT="$R/.claude/scripts/lint-invariants.sh"
    F="$BATS_TEST_TMPDIR/tree"
    mkdir -p "$F/.claude/loa" "$F/.claude/data" "$F/.claude/templates"
    cp -R "$R/.claude/templates/constraints" "$F/.claude/templates/constraints"
    cp "$R/.claude/data/constraints.json" "$F/.claude/data/constraints.json"
    cp "$R/.claude/loa/CLAUDE.loa.md" "$F/.claude/loa/CLAUDE.loa.md"
}

# A kernel that still carries the pre-cycle-129 Agent Teams block, placed
# between the merge constraints and the Agent-Network section as it was.
add_team_block() {
    python3 -I - "$F/.claude/loa/CLAUDE.loa.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = "## Agent-Network Primitives"
block = ("## Agent Teams\n\n| Rule | Why |\n|------|-----|\n"
         "<!-- @constraint-generated: start agent_teams_constraints | hash:0000000000000000 -->\n"
         "<!-- DO NOT EDIT — generated from .claude/data/constraints.json -->\n"
         "| MUST stale row | stale |\n"
         "<!-- @constraint-generated: end agent_teams_constraints -->\n\n")
assert s.count(anchor) == 1
open(p, "w", encoding="utf-8").write(s.replace(anchor, block + anchor))
PY
}

add_team_row() {
    jq '.constraints += [{"id":"C-TEAM-901","name":"fixture_row","category":"agent_teams","rule_type":"MUST",
        "text":"fixture rule","text_variants":{"claude-loa-md":"MUST fixture rule"},"why":"fixture why","order":0,
        "layers":[{"target":"claude-loa-md","section":"agent_teams_constraints","render_as":"table_row"}],
        "severity":"low","source_incident":"#0"}]' "$F/.claude/data/constraints.json" > "$F/c.json"
    mv "$F/c.json" "$F/.claude/data/constraints.json"
}

gen() { (cd "$F" && bash "$GEN" --section "${1:-agent_teams_constraints}"); }

@test "LI-1 constraints.json carries no C-TEAM rows and no agent_teams_constraints layer" {
    run jq '[.constraints[] | select((.id | startswith("C-TEAM")) or any(.layers[]?; .section == "agent_teams_constraints"))] | length' \
        "$R/.claude/data/constraints.json"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "LI-2 the live kernel carries neither the Agent Teams heading nor its marker" {
    # `run` + status, never a bare mid-test `! cmd` (exempt from errexit, so it cannot fail).
    run grep -qxF '## Agent Teams' "$R/.claude/loa/CLAUDE.loa.md"
    [ "$status" -ne 0 ]
    run grep -q 'agent_teams_constraints' "$R/.claude/loa/CLAUDE.loa.md"
    [ "$status" -ne 0 ]
}

@test "LI-3 the generator removes a leftover Agent Teams block when the class is empty" {
    add_team_block
    grep -qxF '## Agent Teams' "$F/.claude/loa/CLAUDE.loa.md"
    run gen
    [ "$status" -eq 0 ]
    run grep -qxF '## Agent Teams' "$F/.claude/loa/CLAUDE.loa.md"
    [ "$status" -ne 0 ]
    run grep -q 'agent_teams_constraints' "$F/.claude/loa/CLAUDE.loa.md"
    [ "$status" -ne 0 ]
    # The neighbouring sections survive with one blank line between them.
    grep -qF '<!-- @constraint-generated: end merge_constraints -->' "$F/.claude/loa/CLAUDE.loa.md"
    run grep -c '^## Agent-Network Primitives$' "$F/.claude/loa/CLAUDE.loa.md"
    [ "$output" = "1" ]
    run diff <(sed -n '/end merge_constraints/,/^## Agent-Network/p' "$F/.claude/loa/CLAUDE.loa.md") \
             <(printf '%s\n' '<!-- @constraint-generated: end merge_constraints -->' '' '## Agent-Network Primitives')
    [ "$status" -eq 0 ]
}

@test "LI-4 pruning is idempotent: a second run leaves the kernel byte-identical" {
    add_team_block
    gen
    cp "$F/.claude/loa/CLAUDE.loa.md" "$F/first.md"
    run gen
    [ "$status" -eq 0 ]
    cmp "$F/first.md" "$F/.claude/loa/CLAUDE.loa.md"
}

@test "LI-5 the generator renders the table when the class has rows" {
    add_team_block
    add_team_row
    run gen
    [ "$status" -eq 0 ]
    grep -qxF '## Agent Teams' "$F/.claude/loa/CLAUDE.loa.md"
    grep -qxF '| MUST fixture rule | fixture why |' "$F/.claude/loa/CLAUDE.loa.md"
    run grep -qF 'MUST stale row' "$F/.claude/loa/CLAUDE.loa.md"
    [ "$status" -ne 0 ]
}

@test "LI-6 rows without the heading block fail loudly and leave the kernel untouched" {
    add_team_row
    cp "$F/.claude/loa/CLAUDE.loa.md" "$F/before.md"
    run gen
    [ "$status" -ne 0 ]
    [[ "$output" == *"Missing markers"*"agent_teams_constraints"* ]]
    cmp "$F/before.md" "$F/.claude/loa/CLAUDE.loa.md"
}

@test "LI-7 a marker block with foreign text above it is an error, not a silent deletion" {
    add_team_block
    python3 -I - "$F/.claude/loa/CLAUDE.loa.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("## Agent Teams\n\n| Rule | Why |", "## Agent Teams\n\nOperator prose that is not a table.\n\n| Rule | Why |")
open(p, "w", encoding="utf-8").write(s)
PY
    cp "$F/.claude/loa/CLAUDE.loa.md" "$F/before.md"
    run gen
    [ "$status" -ne 0 ]
    [[ "$output" == *"no '## Agent Teams' heading directly above its table"* ]]
    cmp "$F/before.md" "$F/.claude/loa/CLAUDE.loa.md"
}

@test "LI-8 lint-invariants passes the optional-table invariant on the live tree" {
    run bash -c "cd '$R' && bash '$LINT' --json"
    local report="$output"
    jq -e '.results[] | select(.message | test("agent_teams_constraints: table presence matches"))' >/dev/null <<<"$report"
    # The negative check is a `run` with a status assertion: a bare mid-test `! cmd`
    # is exempt from errexit and could never fail (review r256-2 LOW-8).
    run jq -e '.results[] | select(.level == "ERROR" and (.message | test("agent_teams")))' <<<"$report"
    [ "$status" -ne 0 ]
    # The field name is load-bearing: the negative check above is vacuous if
    # the report shape ever renames `level`.
    jq -e '[.results[] | has("level")] | all' >/dev/null <<<"$report"
}

@test "LI-9 the lint self-test (test-lint-invariants.sh) is green" {
    run bash -c "cd '$R' && bash .claude/scripts/test-lint-invariants.sh"
    echo "$output" | tail -3
    [ "$status" -eq 0 ]
}
