#!/usr/bin/env bats
# =============================================================================
# #1069 — butterfreezone-gen: 3 residual macOS/BSD defects
# =============================================================================
# 1. Tier-1 capability extraction dropped markdown TABLE rows (grep '^[-*]|^#+')
#    -> empty capabilities -> sparse output failing min_words.
# 2. `sed 's/^./\U&/'` is GNU-only; BSD/macOS sed emits a literal 'U' prefix
#    (Ucompositions, Udata, ...). Replaced by the portable `ucfirst` filter.
# 3. extract_project_description captured a `---` horizontal rule as the README
#    first paragraph -> "purpose: ---".
# =============================================================================

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCRIPT="$PROJECT_ROOT/.claude/scripts/butterfreezone-gen.sh"
    COMPAT="$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    [[ -f "$SCRIPT" ]] || skip "butterfreezone-gen.sh not found"

    export BATS_TMPDIR="${BATS_TMPDIR:-/tmp}"
    export TEST_TMPDIR="$BATS_TMPDIR/bfz-1069-$$"
    mkdir -p "$TEST_TMPDIR"
    export MOCK_REPO="$TEST_TMPDIR/repo"
    mkdir -p "$MOCK_REPO"
    cd "$MOCK_REPO"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"
    mkdir -p src
    echo 'console.log("hi")' > src/index.js
    git add -A && git commit -q -m "init"
}

teardown() {
    cd /
    [[ -n "${TEST_TMPDIR:-}" && -d "$TEST_TMPDIR" ]] && rm -rf "$TEST_TMPDIR"
}

# -----------------------------------------------------------------------------
# Bug 1 — table-row capability extraction
# -----------------------------------------------------------------------------
@test "#1069 bug1: Tier-1 capabilities are extracted from markdown TABLE rows" {
    mkdir -p grimoires/loa/reality
    cat > grimoires/loa/reality/api-surface.md <<'EOF'
# API Surface

This API surface documentation has more than ten words of content to trigger Tier 1 detection here.

## Commands

| Command | Description |
|---------|-------------|
| `deployWidget` | Ships the build to production safely |
| `rollbackWidget` | Reverts to the previous release on demand |
EOF
    git add -A && git commit -q -m "table api-surface"

    run "$SCRIPT" --tier 1
    [ "$status" -eq 0 ]

    # Pre-fix: table rows were dropped (grep '^[-*]|^#+'), so these cells never
    # reached the doc. Post-fix: table rows are lifted into capability bullets.
    run grep -E 'deployWidget|Ships the build to production' BUTTERFREEZONE.md
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Bug 2 — portable first-char upper-casing (no GNU-only \U)
# -----------------------------------------------------------------------------
@test "#1069 bug2: no GNU-only 'sed s/^./\\U&/' remains in butterfreezone-gen.sh" {
    run grep -nE "sed 's/\\^\\./\\\\U" "$SCRIPT"
    [ "$status" -ne 0 ]
}

@test "#1069 bug2: ucfirst helper upper-cases only the first char (portable)" {
    # shellcheck disable=SC1090
    source "$COMPAT"
    [ "$(printf '%s' 'compositions' | ucfirst)" = "Compositions" ]
    [ "$(printf '%s' 'data'         | ucfirst)" = "Data" ]
    [ "$(printf '%s' 'multi word x' | ucfirst)" = "Multi word x" ]
    [ "$(printf '%s' ''             | ucfirst)" = "" ]
}

@test "#1069 bug2: generated module/agent names are not U-prefixed" {
    # Exercise the describe_from_name / module-map paths; assert no 'U'-prefixed
    # artifacts like 'Ucompositions' / 'Udata' leak into the output.
    mkdir -p compositions data modules
    echo x > compositions/a.txt; echo y > data/b.txt; echo z > modules/c.txt
    git add -A && git commit -q -m "dirs"
    run "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]
    run grep -E '\bU(compositions|data|modules|templates|observatory)\b' <<<"$output"
    [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# Bug 3 — '---' horizontal rule must not become the project description
# -----------------------------------------------------------------------------
@test "#1069 bug3: README horizontal rule is not captured as purpose" {
    cat > README.md <<'EOF'
# My Project

[![ci](https://img.shields.io/badge/ci-pass-green.svg)](https://example.com)

---

My Project does a specific and useful thing for developers and their teams.
EOF
    git add -A && git commit -q -m "readme with hr"

    run "$SCRIPT" --dry-run
    [ "$status" -eq 0 ]

    # The AGENT-CONTEXT purpose must be the real paragraph, never the rule.
    purpose_line=$(printf '%s\n' "$output" | grep -iE 'purpose:' | head -1)
    [[ "$purpose_line" != *"---"* ]]
    [[ "$purpose_line" == *"specific and useful thing"* ]]
}
