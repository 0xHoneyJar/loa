#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    SCRIPT="$REPO_ROOT/.claude/scripts/validate-artifact.sh"
    TEMPLATE="$REPO_ROOT/.claude/skills/bug-triaging/resources/templates/triage.md"
    export REAL_SED="$(command -v sed)"
    export REAL_GREP="$(command -v grep)"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    # Exercise the POSIX regex dialect in both tools, without GNU's \s.
    cat > "$BATS_TEST_TMPDIR/bin/sed" <<'PY'
#!/usr/bin/env python3
import os
import sys
program = os.path.basename(sys.argv[0])
os.execv(os.environ["REAL_" + program.upper()],
         [program] + [a.replace(r"\s", "s") for a in sys.argv[1:]])
PY
    chmod +x "$BATS_TEST_TMPDIR/bin/sed"
    cp "$BATS_TEST_TMPDIR/bin/sed" "$BATS_TEST_TMPDIR/bin/grep"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
    BUG_ID=20260715-i155-f3acb3
    mkdir -p "$PROJECT_ROOT/.run/bugs/$BUG_ID"
    printf '{"schema_version":1,"bug_id":"%s"}\n' "$BUG_ID" \
        > "$PROJECT_ROOT/.run/bugs/$BUG_ID/state.json"
    "$REAL_SED" "s/{bug_id}/$BUG_ID/g" "$TEMPLATE" > "$BATS_TEST_TMPDIR/triage.md"
}

@test "#1216: BSD sed accepts the shipped triage template verbatim" {
    run bash "$SCRIPT" --type bug-triage --file "$BATS_TEST_TMPDIR/triage.md" --json
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "#1216: whitespace variants parse and missing state still fails" {
    printf '\t- \t**bug_id**:\t%s \n' "$BUG_ID" > "$BATS_TEST_TMPDIR/triage.md"
    run bash "$SCRIPT" --type bug-triage --file "$BATS_TEST_TMPDIR/triage.md"
    echo "$output"
    [ "$status" -eq 0 ]
    rm "$PROJECT_ROOT/.run/bugs/$BUG_ID/state.json"
    run bash "$SCRIPT" --type bug-triage --file "$BATS_TEST_TMPDIR/triage.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"sibling state.json not found"* ]]
    [[ "$output" != *"does not match"* ]]
}

@test "#1216: malformed IDs still fail under BSD sed" {
    printf '%s\n' '- **bug_id**: malformed' > "$BATS_TEST_TMPDIR/triage.md"
    run bash "$SCRIPT" --type bug-triage --file "$BATS_TEST_TMPDIR/triage.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bug_id 'malformed' does not match"* ]]
}
