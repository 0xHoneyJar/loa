#!/usr/bin/env bats
# =============================================================================
# tests/unit/glossary-terms.bats
#
# tools/check-glossary-terms.sh (grimoires/loa/sdd.md D-6.2, §5.3) keeps every
# backticked span of the kernel that matches ^[A-Za-z][A-Za-z0-9_-]*$ outside
# fenced code and fails unless each one resolves to a glossary **Term**, an
# _Aliases_: token (case-insensitive, plural s/es folded) or an allowlist line
# (at most 30). Every case below works on temp copies; the live kernel,
# glossary and allowlist are only ever read.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    CHECK="$PROJECT_ROOT/tools/check-glossary-terms.sh"
    KERNEL="$PROJECT_ROOT/.claude/loa/CLAUDE.loa.md"
    GLOSSARY="$PROJECT_ROOT/.claude/loa/GLOSSARY.md"
    ALLOW="$PROJECT_ROOT/.claude/data/glossary-allowlist.txt"
    FIX="$PROJECT_ROOT/tests/fixtures/glossary"
    W="$BATS_TEST_TMPDIR"
    printf '# Glossary: t\nTest vocabulary.\n\n## Language\n\n**Widget**: A thing.\n\n**Run mode**: Unattended runs.\n_Aliases_: RUNNING, JACKED_OUT\n\n**Box**: A container.\n' > "$W/g.md"
    printf '# test allowlist\nparse_it   # code identifier\n' > "$W/a.txt"
}

# check <kernel text>: run the checker on a temp kernel with the temp glossary and allowlist
check() {
    printf '%s\n' "$1" > "$W/k.md"
    shift
    run "$CHECK" --kernel "$W/k.md" --glossary "$W/g.md" --allowlist "$W/a.txt" "$@"
}

@test "GT-1 the live kernel, framework glossary and allowlist pass" {
    run "$CHECK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"missing: 0"* ]]
    [[ "$output" == *"PASS"* ]]
    # the only WARN is the advisory alias ratio (the kernel names no glossary
    # term in backticks; sprint-254 review item 1)
    [ "$(grep -c '^WARN:' <<< "$output")" -eq 1 ]
    [[ "$output" == *"WARN: advisory: 5 kernel token(s) resolve through _Aliases_: lines and 0 through **Term** entries"* ]]
}

@test "GT-2 removing a term from a copy of the glossary fails and names the token" {
    grep -v '^_Aliases_: br$' "$GLOSSARY" > "$W/glossary.md"
    run "$CHECK" --glossary "$W/glossary.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *'MISS: `br`'* ]]
    [[ "$output" == *"define **br**"* ]]
    [[ "$output" == *"_Aliases_: line"* ]]
    [[ "$output" == *"allowlist it in"* ]]
}

@test "GT-3 removing the run mode entry from a copy fails on each of its aliases" {
    awk '/^\*\*Run mode\*\*:/ { skip = 1; next } skip && /^_Aliases_:/ { skip = 0; next } { skip = 0; print }' "$GLOSSARY" > "$W/glossary.md"
    run "$CHECK" --glossary "$W/glossary.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *'MISS: `RUNNING`'* ]]
    [[ "$output" == *'MISS: `HALTED`'* ]]
    [[ "$output" == *'MISS: `JACKED_OUT`'* ]]
}

@test "GT-4 matching is case-insensitive and folds s and es plurals" {
    check 'Use a `widget`, two `Widgets`, `boxes` and `BOX`.' --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"defined     widget"*"-> Widget"* ]]
    [[ "$output" == *"defined     Widgets"* ]]
    [[ "$output" == *"defined     boxes"*"-> Box"* ]]
    [[ "$output" == *"defined     BOX"* ]]
}

@test "GT-4b a singular token resolves to a plural term" {
    printf '# Glossary: t\nctx\n\n## Language\n\n**Beads**: A tracker.\n\n**Matches**: Pairs.\n' > "$W/g.md"
    check 'One `bead`, one `match`, many `BEADS`.' --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"defined     bead "*"-> Beads"* ]]
    [[ "$output" == *"defined     match "*"-> Matches"* ]]
}

@test "GT-5 an _Aliases_: token resolves to its entry; a multi-word term matches with - or _" {
    check 'States: `running`, `JACKED_OUT`; also `run-mode` and `run_mode`.' --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"alias       running"*"-> Run mode"* ]]
    [[ "$output" == *"alias       JACKED_OUT"*"-> Run mode"* ]]
    [[ "$output" == *"defined     run-mode"*"-> Run mode"* ]]
    [[ "$output" == *"defined     run_mode"*"-> Run mode"* ]]
}

@test "GT-6 an undefined token fails; a token close to a term does not resolve by accident" {
    check 'A `Widgetry` and a `Sprocket`.'
    [ "$status" -eq 1 ]
    [[ "$output" == *'MISS: `Widgetry`'* ]]
    [[ "$output" == *'MISS: `Sprocket`'* ]]
    [[ "$output" == *"missing: 2"* ]]
}

@test "GT-7 tokens inside fenced code are ignored (backtick and tilde fences)" {
    check $'Prose `Widget`.\n```bash\necho `Sprocket`\n```\n~~~\n`Gizmo`\n~~~\n  ```\n  `Indented`\n  ```'
    [ "$status" -eq 0 ]
    [[ "$output" == *"kernel tokens kept: 1;"* ]]
}

@test "GT-8 the shape heuristic drops paths, files, flags, keys, calls, commands, phrases and operators" {
    check 'Dropped: `a/b`, `file.md`, `--flag`, `-x`, `key: value`, `audit: skip`, `a:b:c`, `:lead`, `trail:`, `x::y`, `flatline:<path>`, `call()`, `/loa`, `two words`, `>>`, `*_TEST_MODE=1`, `9lives`, `x=y`.' --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"kernel tokens kept: 0;"* ]]
}

@test "GT-8b one interior colon is kept: decision:grilling resolves to its entry, a typo misses" {
    printf '# Glossary: t\nctx\n\n## Language\n\n**decision:grilling**: A label.\n' > "$W/g.md"
    check 'Label `decision:grilling`, `Decision:Grilling` and the typo `decision:griling`.' --report
    [ "$status" -eq 1 ]
    [[ "$output" == *"defined     decision:grilling"*"-> decision:grilling"* ]]
    [[ "$output" == *"defined     Decision:Grilling"* ]]
    [[ "$output" == *'MISS: `decision:griling`'* ]]
}

@test "GT-8c the live framework glossary resolves all four decision labels" {
    printf 'Labels: `decision:grilling`, `decision:prototype`, `decision:research`, `decision:unblock`.\n' > "$W/k.md"
    run "$CHECK" --kernel "$W/k.md" --allowlist "$W/a.txt" --report
    [ "$status" -eq 0 ]
    [ "$(grep -c '^defined     decision:' <<< "$output")" -eq 4 ]
}

@test "GT-9 an allowlisted token resolves; an allowlist of 31 entries fails" {
    check 'Call `parse_it`.' --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"allowlisted parse_it"* ]]
    : > "$W/a.txt"
    for i in $(seq 1 31); do printf 'tok%02d  # reason\n' "$i" >> "$W/a.txt"; done
    check 'Call `tok01`.'
    [ "$status" -eq 1 ]
    [[ "$output" == *"has 31 entries, over the limit of 30"* ]]
}

@test "GT-10 an allowlist of exactly 30 entries passes (stale entries only WARN)" {
    : > "$W/a.txt"
    for i in $(seq 1 30); do printf 'tok%02d  # reason\n' "$i" >> "$W/a.txt"; done
    check 'Call `tok01`.'
    [ "$status" -eq 0 ]
    [[ "$output" == *"allowlist entries: 30/30"* ]]
}

@test "GT-11 a stale allowlist entry WARNs and still exits 0; a redundant one WARNs too" {
    printf 'parse_it  # used\ngone_fn   # no longer in the kernel\nwidget    # the glossary defines it\n' > "$W/a.txt"
    check 'Call `parse_it` on a `Widget`.'
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: allowlist entry 'gone_fn'"*"no longer occurs"* ]]
    [[ "$output" == *"WARN: allowlist entry 'widget'"*"already resolved by the glossary entry **Widget**"* ]]
}

@test "GT-12 --json carries the report fields" {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    printf 'parse_it  # used\ngone_fn   # stale\n' > "$W/a.txt"
    check 'A `Widget`, `running`, `parse_it` and a `Sprocket`.' --json
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '
        .ok == false and .kept == 4
        and .counts == {defined: 1, alias: 1, allowlisted: 1, missing: 1}
        and .missing == ["Sprocket"] and .stale_allowlist == ["gone_fn"]
        and .allowlist_entries == 2 and .allowlist_max == 30
        and (.tokens | map(.resolution)) == ["defined", "alias", "allowlisted", "MISS"]
        and (.tokens[0] | .token == "Widget" and .line == 1 and .entry == "Widget")
        and (.tokens[3].entry == null)
        and (.violations | length) == 1 and (.warnings | length) == 1' >/dev/null
}

@test "GT-13 --json on the live files reports ok with zero misses" {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
    run "$CHECK" --json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.ok == true and .counts.missing == 0 and .kept > 0 and .allowlist_entries <= 30' >/dev/null
}

@test "GT-14 the miss fixture exits 1 (positive control)" {
    run "$CHECK" --kernel "$FIX/miss/kernel.md" --glossary "$FIX/miss/GLOSSARY.md" --allowlist "$FIX/miss/allowlist.txt"
    [ "$status" -eq 1 ]
    [[ "$output" == *'MISS: `Sprocket`'* ]]
}

@test "GT-15 the ok fixture exits 0 (negative control)" {
    run "$CHECK" --kernel "$FIX/ok/kernel.md" --glossary "$FIX/ok/GLOSSARY.md" --allowlist "$FIX/ok/allowlist.txt" --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"kernel tokens kept: 4; defined: 2; alias: 1; allowlisted: 1; missing: 0"* ]]
}

@test "GT-16 usage errors exit 2: unknown flag, missing path, unreadable file" {
    run "$CHECK" --bogus
    [ "$status" -eq 2 ]
    run "$CHECK" --kernel
    [ "$status" -eq 2 ]
    run "$CHECK" --glossary "$W/nope.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"cannot read"* ]]
}

@test "GT-17 entries outside ## Language do not resolve tokens" {
    printf '# Glossary: t\nctx\n\n**Widget**: Above the language section.\n\n## Language\n\n**Box**: A container.\n\n## Notes\n\n**Gizmo**: In a later section.\n' > "$W/g.md"
    check 'A `Widget`, a `Box`, a `Gizmo`.'
    [ "$status" -eq 1 ]
    [[ "$output" == *'MISS: `Widget`'* ]]
    [[ "$output" == *'MISS: `Gizmo`'* ]]
    [[ "$output" != *'MISS: `Box`'* ]]
}

@test "GT-18 the live allowlist stays within 30 entries and every entry carries a reason" {
    n="$(grep -vE '^[[:space:]]*(#|$)' "$ALLOW" | wc -l | tr -d ' ')"
    [ "$n" -le 30 ]
    run grep -vE '^[[:space:]]*(#|$)' "$ALLOW"
    while IFS= read -r line; do
        [[ "$line" == *"#"?* ]] || { echo "no reason: $line"; return 1; }
    done <<< "$output"
}

@test "GT-19 the framework glossary has at least 18 entries" {
    n="$(grep -cE '^\*\*[^*]+\*\*: ' "$GLOSSARY")"
    [ "$n" -ge 18 ]
}

@test "GT-20 kernel fences close only on the same character and length (CommonMark)" {
    check $'A `Widget`.\n````md\n```\n`Hidden1`\n```\n````\nThen `Box`.\n```\n~~~\n`Hidden2`\n~~~\n```\nAnd `Widgets`.\n~~~~\n```\n`Hidden3`\n~~~~~\nEnd.' --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"kernel tokens kept: 3;"* ]]
    [[ "$output" != *"Hidden"* ]]
}

@test "GT-21 an inline triple-backtick span does not open a fence; spans match backtick runs of equal length" {
    check $'Inline ```Code``` here, ``a `Widget` b`` there, and a `Sprocket`.\nNext line `Box`.' --report
    [ "$status" -eq 1 ]
    [[ "$output" == *'MISS: `Code`'* ]]
    [[ "$output" == *'MISS: `Sprocket`'* ]]
    [[ "$output" == *"defined     Box"* ]]
    [[ "$output" == *"kernel tokens kept: 3;"* ]]
}

@test "GT-22 glossary fences follow the same rule: entries in a nested block do not count" {
    printf '# Glossary: t\nctx\n\n## Language\n\n````md\n```\n**Ghost**: inside the block.\n```\n````\n\n**Widget**: A thing.\n' > "$W/g.md"
    check 'A `Widget` and a `Ghost`.'
    [ "$status" -eq 1 ]
    [[ "$output" == *'MISS: `Ghost`'* ]]
    [[ "$output" != *'MISS: `Widget`'* ]]
}

@test "GT-23 an orphan _Aliases_: line WARNs with its glossary line and does not shadow a later alias" {
    printf '# Glossary: t\nctx\n\n## Language\n\n_Aliases_: wid\n\n**Widget**: A thing, also wid.\n_Aliases_: wid\n' > "$W/g.md"
    check 'A `wid`.' --report
    [ "$status" -eq 0 ]
    [[ "$output" == *"alias       wid"*"-> Widget"* ]]
    [[ "$output" == *"WARN: _Aliases_: line $W/g.md:6 comes before any **Term**: entry"* ]]
}

@test "GT-24 one alias line naming every kernel token passes the checker with the advisory WARN, and the validator fails it" {
    toks="$("$CHECK" --report 2>/dev/null | awk '$1 ~ /^(alias|allowlisted|defined)$/ {print $2}' | paste -sd, - | sed 's/,/, /g')"
    [ -n "$toks" ]
    printf '# Glossary: t\nctx\n\n## Language\n\n**Stuff**: Everything.\n_Aliases_: %s\n' "$toks" > "$W/g.md"
    : > "$W/a.txt"
    run "$CHECK" --glossary "$W/g.md" --allowlist "$W/a.txt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN: advisory: 16 kernel token(s) resolve through _Aliases_: lines and 0 through **Term** entries"* ]]
    run "$PROJECT_ROOT/.claude/scripts/validate-artifact.sh" --type glossary --file "$W/g.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *'"Stuff" has 16 aliases, over 6'* ]]
}

@test "GT-25 no advisory WARN when defined terms outnumber alias resolutions" {
    check 'A `Widget`, a `Box` and `running`.'
    [ "$status" -eq 0 ]
    [[ "$output" != *"advisory"* ]]
}

@test "GT-26 --json avoids jq 1.6-only features (jq 1.5 portability)" {
    run bash -c 'grep -vE "^[[:space:]]*#" "$1" | grep -nE -- "--rawfile|[^A-Za-z_]IN\\("' _ "$CHECK"
    [ "$status" -eq 1 ]
}

@test "GT-27 a line that starts with an inline triple-backtick span is text, not a fence opener" {
    check $'```Code``` starts this line and a `Sprocket` follows.\nThen a `Gizmo`.'
    [ "$status" -eq 1 ]
    [[ "$output" == *'MISS: `Sprocket`'* ]]
    [[ "$output" == *'MISS: `Gizmo`'* ]]
}

@test "GT-28 a double-backtick span holding a single backtick is one span, not two" {
    check $'Here ``Foo`Bar`` and a `Widget`.' --report
    [ "$status" -eq 0 ]
    [[ "$output" != *"Foo"* ]]
    [[ "$output" == *"kernel tokens kept: 1;"* ]]
}
