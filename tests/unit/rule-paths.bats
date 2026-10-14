#!/usr/bin/env bats
# Path-scoped rule files (grimoires/loa/sdd.md D-3.1, DEC-0129): stash-safety.md and
# skill-invariants.md carry `paths:` frontmatter, the frontmatter parses, and every glob
# matches at least one tracked file of the kind the rule is about (git pathspec glob
# semantics: `**` spans directories, `*` stays inside one).

setup() {
    PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    RULES="$PROJECT_ROOT/.claude/rules"
    command -v yq >/dev/null 2>&1 || skip "yq not installed"
}

# The YAML between the first two '---' lines (empty when the file has none).
frontmatter() { awk 'NR == 1 && $0 != "---" { exit } /^---$/ { if (n++) exit; next } n' "$1"; }
globs() { frontmatter "$1" | yq eval '.paths[]' -; }
tracked() { git -C "$PROJECT_ROOT" ls-files -- ":(glob)$1"; }

@test "RP-1 both rule files open with frontmatter that parses and lists string globs under paths:" {
    local f n
    for f in stash-safety.md skill-invariants.md; do
        [ "$(head -1 "$RULES/$f")" = "---" ] || { echo "$f has no frontmatter"; return 1; }
        frontmatter "$RULES/$f" | yq eval '.' - >/dev/null || { echo "$f frontmatter does not parse"; return 1; }
        [ "$(frontmatter "$RULES/$f" | yq eval '.paths | type' -)" = "!!seq" ]
        n="$(frontmatter "$RULES/$f" | yq eval '.paths | length' -)"
        [ "$n" -ge 1 ]
        [ "$(frontmatter "$RULES/$f" | yq eval '[.paths[] | select(type != "!!str")] | length' -)" -eq 0 ]
    done
}

@test "RP-2 the globs are the ones the SDD names" {
    [ "$(globs "$RULES/stash-safety.md" | tr '\n' ' ')" = '**/*.sh **/*.bats .claude/scripts/** .claude/hooks/** ' ]
    [ "$(globs "$RULES/skill-invariants.md" | tr '\n' ' ')" = '.claude/skills/**/SKILL.md .claude/agents/** .claude/data/agent-types.yaml .claude/scripts/validate-skill-capabilities.sh ' ]
}

@test "RP-3 every stash-safety glob matches a tracked shell source" {
    local g hits
    while IFS= read -r g; do
        hits="$(tracked "$g" | grep -E '\.(sh|bats)$' | head -1)"
        [ -n "$hits" ] || { echo "glob '$g' matches no tracked .sh/.bats file"; return 1; }
    done < <(globs "$RULES/stash-safety.md")
}

@test "RP-4 every skill-invariants glob matches a tracked skill, agent definition or capability file" {
    local g hits
    while IFS= read -r g; do
        hits="$(tracked "$g" | grep -E '(^\.claude/skills/[^/]+/SKILL\.md$|^\.claude/agents/[^/]+\.md$|^\.claude/data/agent-types\.yaml$|^\.claude/scripts/validate-skill-capabilities\.sh$)' | head -1)"
        [ -n "$hits" ] || { echo "glob '$g' matches no tracked file of the intended kind"; return 1; }
    done < <(globs "$RULES/skill-invariants.md")
}

@test "RP-5 path-scoping removed no rule text: the body after the frontmatter keeps its heading and sections" {
    local body
    body="$(awk '/^---$/ && c < 2 { c++; next } c >= 2' "$RULES/stash-safety.md")"
    [[ "$body" == *"# Git Stash Safety"* && "$body" == *"## Judgment rules the fence cannot express"* ]]
    body="$(awk '/^---$/ && c < 2 { c++; next } c >= 2' "$RULES/skill-invariants.md")"
    [[ "$body" == *"# Skill Frontmatter Invariants"* && "$body" == *"## The invariant"* ]]
}

@test "RP-6 the rule-lifecycle validator accepts both files (origin, version, enacted_by)" {
    run "$PROJECT_ROOT/.claude/scripts/validate-rule-lifecycle.sh" --json
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}
