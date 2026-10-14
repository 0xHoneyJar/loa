#!/usr/bin/env bats
# =============================================================================
# user-invoked-commands.bats: the operator-only command allowlist (FR-8, D-8.3)
# =============================================================================
# `.claude/data/user-invoked-commands.txt` lists commands carrying
# `disable-model-invocation: true`. The harness refuses those to the Skill
# tool (tests/unit/user-invoked-harness.bats), so no other command or skill
# body may tell the model to run one as a step. Asserts:
#   1. every listed command file exists and carries the flag
#   2. no other body has an operative line for a listed name
#   3. every command file carrying the flag is listed
#   4. no SKILL.md allowed-tools grants dec-write-lib.sh confirm, supersede
#      or context --clear (those are reachable only through /decisions)
# Each check is a function over a root directory, proved against fixtures.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export LC_ALL=C
}

# list_names <root>: the allowlisted names, comments and blanks stripped
list_names() {
    sed -e 's/#.*$//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' \
        "$1/.claude/data/user-invoked-commands.txt" | grep -v '^$' || true
}

# frontmatter <file>: the first YAML frontmatter block (empty when none)
frontmatter() {
    awk 'NR==1 && $0!="---"{exit} /^---[[:space:]]*$/{n++; if(n==2) exit; next} n==1{print}' "$1"
}

has_flag() {
    frontmatter "$1" | grep -Eq '^disable-model-invocation:[[:space:]]*"?true"?[[:space:]]*$'
}

# check_listed_flagged <root>: prints each listed name whose file is missing or unflagged
check_listed_flagged() {
    local root="$1" name f
    while IFS= read -r name; do
        f="$root/.claude/commands/$name.md"
        if [[ ! -f "$f" ]]; then
            echo "missing: $name"
        elif ! has_flag "$f"; then
            echo "unflagged: $name"
        fi
    done < <(list_names "$root")
}

# check_flagged_listed <root>: prints each flagged command file not in the list
check_flagged_listed() {
    local root="$1" f name names
    names="$(list_names "$root")"
    for f in "$root"/.claude/commands/*.md; do
        [[ -f "$f" ]] || continue
        has_flag "$f" || continue
        name="$(basename "$f" .md)"
        grep -qxF "$name" <<<"$names" || echo "unlisted: $name"
    done
}

# check_operative <root>: prints file:line for each operative reference to a
# listed name in a body other than that command's own file
check_operative() {
    local root="$1" name re exempt
    exempt='(^|[^[:alpha:]])(user|operator|human|manually|suggest|recommend|tell|ask)'
    while IFS= read -r name; do
        # SDD D-8.3 pattern, widened: verbs match in any case and may take
        # "the" ("execute /x", "Invoke the /x skill").
        re="([Ee][Xx][Ee][Cc][Uu][Tt][Ee]|[Ii][Nn][Vv][Oo][Kk][Ee]|[Rr][Uu][Nn]|[Cc][Aa][Ll][Ll])[[:space:]]+(the[[:space:]]+)?\`?/${name}([^[:alnum:]_-]|\$)|Skill\\(.*${name}"
        { find "$root/.claude/commands" -name '*.md' -type f 2>/dev/null
          find "$root/.claude/skills" -name '*.md' -type f 2>/dev/null; } |
        while IFS= read -r f; do
            [[ "$f" == "$root/.claude/commands/$name.md" ]] && continue
            grep -nE "$re" "$f" 2>/dev/null | grep -viE "$exempt" |
                sed "s|^|${f#"$root"/}:|" || true
        done
    done < <(list_names "$root")
}

# check_operator_ops <root>: prints SKILL.md files whose allowed-tools grant
# an operator-only dec-write-lib.sh operation
check_operator_ops() {
    local root="$1" f
    while IFS= read -r f; do
        frontmatter "$f" | awk '/^allowed-tools:/{on=1; print; next} on && /^[[:space:]]+-|^[[:space:]]+[^[:space:]]/{print; next} {on=0}' |
            grep -Eq 'dec-write-lib\.sh[^,)]*(confirm|supersede|context[[:space:]]+--clear)' && echo "${f#"$root"/}"
    done < <(find "$root/.claude/skills" -name SKILL.md -type f 2>/dev/null)
    return 0
}

make_fixture() {
    local r="$BATS_TEST_TMPDIR/fx"
    mkdir -p "$r/.claude/data" "$r/.claude/commands" "$r/.claude/skills/demo"
    printf 'alpha   # reason\n\n# comment\nbeta\n' > "$r/.claude/data/user-invoked-commands.txt"
    printf -- '---\nname: alpha\ndisable-model-invocation: true\n---\nbody\n' > "$r/.claude/commands/alpha.md"
    printf -- '---\nname: beta\ndisable-model-invocation: true\n---\nRun `/alpha` from another command body.\n' > "$r/.claude/commands/beta.md"
    printf -- '---\nname: demo\nallowed-tools: Read, Grep\n---\nTell the user to Run /alpha when ready.\n' > "$r/.claude/skills/demo/SKILL.md"
    echo "$r"
}

# ---------------------------------------------------------------------------
# Live tree
# ---------------------------------------------------------------------------

@test "allowlist exists and lists the safe set and gpt-review" {
    [ -f "$PROJECT_ROOT/.claude/data/user-invoked-commands.txt" ]
    run list_names "$PROJECT_ROOT"
    for n in gpt-review loa-eject toggle-gpt-review permission-audit loa-setup; do
        grep -qxF "$n" <<<"$output"
    done
}

@test "every listed command file exists and carries the flag" {
    run check_listed_flagged "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "$output"; false; }
}

@test "every command file carrying the flag is listed" {
    run check_flagged_listed "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "$output"; false; }
}

@test "no other body has an operative line for a listed command" {
    run check_operative "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "$output"; false; }
}

@test "no SKILL.md allowed-tools grants dec-write-lib.sh confirm, supersede or context --clear" {
    run check_operator_ops "$PROJECT_ROOT"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "$output"; false; }
}

@test "the /decisions command, once present, is flagged and listed" {
    local f="$PROJECT_ROOT/.claude/commands/decisions.md"
    [[ -f "$f" ]] || skip "decisions.md not landed in this tree"
    has_flag "$f"
    list_names "$PROJECT_ROOT" | grep -qxF decisions
}

# ---------------------------------------------------------------------------
# Fixtures: each check fails when its invariant breaks
# ---------------------------------------------------------------------------

@test "fixture: clean tree passes every check" {
    local r; r="$(make_fixture)"
    printf -- '---\nname: beta\ndisable-model-invocation: true\n---\nplain body\n' > "$r/.claude/commands/beta.md"
    [ -z "$(check_listed_flagged "$r")" ]
    [ -z "$(check_flagged_listed "$r")" ]
    [ -z "$(check_operative "$r")" ]
    [ -z "$(check_operator_ops "$r")" ]
}

@test "fixture: a listed command without the flag or file is reported" {
    local r; r="$(make_fixture)"
    printf -- '---\nname: alpha\n---\nbody\n' > "$r/.claude/commands/alpha.md"
    echo "gamma" >> "$r/.claude/data/user-invoked-commands.txt"
    run check_listed_flagged "$r"
    [[ "$output" == *"unflagged: alpha"* ]]
    [[ "$output" == *"missing: gamma"* ]]
}

@test "fixture: the flag outside the frontmatter does not count" {
    local r; r="$(make_fixture)"
    printf -- '---\nname: alpha\n---\ndisable-model-invocation: true\n' > "$r/.claude/commands/alpha.md"
    run check_listed_flagged "$r"
    [[ "$output" == *"unflagged: alpha"* ]]
}

@test "fixture: a flagged command missing from the list is reported" {
    local r; r="$(make_fixture)"
    printf -- '---\nname: delta\ndisable-model-invocation: true\n---\n' > "$r/.claude/commands/delta.md"
    run check_flagged_listed "$r"
    [ "$output" = "unlisted: delta" ]
}

@test "fixture: operative references are caught, advice and the own file are not" {
    local r; r="$(make_fixture)"
    cat > "$r/.claude/skills/demo/SKILL.md" <<'EOF'
---
name: demo
---
Execute `/alpha` to finish.
Invoke /beta --force
Then call Skill(alpha) directly.
Tell the user to Run /alpha when ready.
Suggest Run /beta if stuck.
Run /alphabet is a different command.
Run `/alpha-two` is a different command too.
then execute /alpha now.
Invoke the `/beta` skill.
EOF
    run check_operative "$r"
    [[ "$output" == *"SKILL.md:4:Execute"* ]]
    [[ "$output" == *"SKILL.md:5:Invoke /beta"* ]]
    [[ "$output" == *"SKILL.md:6:Then call Skill(alpha)"* ]]
    [[ "$output" != *":7:"* ]]
    [[ "$output" != *":8:"* ]]
    [[ "$output" != *"alphabet"* ]]
    [[ "$output" != *"alpha-two"* ]]
    [[ "$output" == *"SKILL.md:11:then execute /alpha"* ]]
    [[ "$output" == *"SKILL.md:12:Invoke the"* ]]
    # beta.md mentions Run `/alpha`: another body, so it is caught too
    [[ "$output" == *"commands/beta.md:5:"* ]]
}

@test "fixture: a skill granting dec-write-lib.sh confirm is reported" {
    local r; r="$(make_fixture)"
    printf -- '---\nname: demo\nallowed-tools: Read, Bash(.claude/scripts/lib/dec-write-lib.sh confirm *)\n---\n' > "$r/.claude/skills/demo/SKILL.md"
    run check_operator_ops "$r"
    [ "$output" = ".claude/skills/demo/SKILL.md" ]
    printf -- '---\nname: demo\nallowed-tools:\n  - Read\n  - Bash(.claude/scripts/lib/dec-write-lib.sh context --clear)\n---\n' > "$r/.claude/skills/demo/SKILL.md"
    run check_operator_ops "$r"
    [ "$output" = ".claude/skills/demo/SKILL.md" ]
    printf -- '---\nname: demo\nallowed-tools: Read, Bash(.claude/scripts/lib/dec-write-lib.sh new *)\n---\n' > "$r/.claude/skills/demo/SKILL.md"
    run check_operator_ops "$r"
    [ -z "$output" ]
}
