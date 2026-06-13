#!/usr/bin/env bats
# =============================================================================
# tests/integration/check-no-swallowed-jq.bats
#
# sprint-bug-208 / #1025 — tools/check-no-swallowed-jq.sh scanner contract.
#
# The scanner is the CI tripwire fencing the output-swallowing class
# (`jq … 2>/dev/null || echo <default>` and the `|| echo`-without-stderr-
# suppression variant) on gate-critical scripts — the KF-004/KF-015
# mechanism. Modeled on tools/check-no-raw-sha256sum.sh (KF-012 precedent).
#
# Contract proven here:
#   SW-1:  flags the canonical shape (exit 1, file:line printed)
#   SW-2:  flags the variant without 2>/dev/null
#   SW-3:  clean file (jq_strict usage, plain jq without || echo) passes
#   SW-4:  suppression marker `# check-no-swallowed-jq: ok` is honored
#   SW-5:  line-leading comments are skipped
#   SW-6:  non-script files are ignored in --root mode
#   SW-7:  extensionless file with bash shebang IS scanned (DISS-002 class)
#   SW-8:  unknown argument → exit 2
#   SW-9:  --root pointing nowhere → exit 2
#   SW-10: default mode (enforced gate-critical set) is green on this repo
#   SW-11: --quiet emits no violation listing but keeps the exit code
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    SCANNER="$PROJECT_ROOT/tools/check-no-swallowed-jq.sh"

    FIX_DIR="$BATS_TEST_TMPDIR/fixtures"
    mkdir -p "$FIX_DIR"
}

@test "scanner: flags the canonical swallow shape with file:line (SW-1)" {
    cat > "$FIX_DIR/bad.sh" <<'EOF'
#!/usr/bin/env bash
count=$(echo "$payload" | jq '.findings | length' 2>/dev/null || echo "0")
EOF
    run bash "$SCANNER" --root "$FIX_DIR"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"bad.sh:2"* ]]
}

@test "scanner: flags the || echo variant without stderr suppression (SW-2)" {
    cat > "$FIX_DIR/bad2.sh" <<'EOF'
#!/usr/bin/env bash
status=$(jq -r '.status' "$f" || echo "unknown")
EOF
    run bash "$SCANNER" --root "$FIX_DIR"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"bad2.sh:2"* ]]
}

@test "scanner: clean file passes (SW-3)" {
    cat > "$FIX_DIR/clean.sh" <<'EOF'
#!/usr/bin/env bash
source .claude/scripts/compat-lib.sh
if ! count=$(echo "$payload" | jq_strict '.findings | length'); then
    echo "ERROR: payload unparseable" >&2
    exit 5
fi
plain=$(echo "$payload" | jq -r '.name')
EOF
    run bash "$SCANNER" --root "$FIX_DIR"
    [[ "$status" -eq 0 ]]
}

@test "scanner: suppression marker is honored (SW-4)" {
    cat > "$FIX_DIR/suppressed.sh" <<'EOF'
#!/usr/bin/env bash
count=$(jq '.n' "$f" 2>/dev/null || echo "0")  # check-no-swallowed-jq: ok (pending #1025 sweep)
EOF
    run bash "$SCANNER" --root "$FIX_DIR"
    [[ "$status" -eq 0 ]]
}

@test "scanner: line-leading comments are skipped (SW-5)" {
    cat > "$FIX_DIR/commented.sh" <<'EOF'
#!/usr/bin/env bash
# the forbidden shape is: count=$(jq '.n' "$f" 2>/dev/null || echo "0")
true
EOF
    run bash "$SCANNER" --root "$FIX_DIR"
    [[ "$status" -eq 0 ]]
}

@test "scanner: non-script files are ignored in --root mode (SW-6)" {
    cat > "$FIX_DIR/notes.md" <<'EOF'
count=$(jq '.n' "$f" 2>/dev/null || echo "0")
EOF
    run bash "$SCANNER" --root "$FIX_DIR"
    [[ "$status" -eq 0 ]]
}

@test "scanner: extensionless bash-shebang file IS scanned (SW-7)" {
    cat > "$FIX_DIR/extensionless-tool" <<'EOF'
#!/usr/bin/env bash
count=$(jq '.n' "$f" 2>/dev/null || echo "0")
EOF
    run bash "$SCANNER" --root "$FIX_DIR"
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"extensionless-tool:2"* ]]
}

@test "scanner: unknown argument exits 2 (SW-8)" {
    run bash "$SCANNER" --bogus-flag
    [[ "$status" -eq 2 ]]
}

@test "scanner: nonexistent --root exits 2 (SW-9)" {
    run bash "$SCANNER" --root "$BATS_TEST_TMPDIR/does-not-exist"
    [[ "$status" -eq 2 ]]
}

@test "scanner: default mode (enforced gate-critical set) is green on this repo (SW-10)" {
    # This is the 'scanner lands green' acceptance criterion from #1025:
    # migrated sites use jq_strict; un-migrated gate-critical sites carry
    # explicit per-line suppression markers with a tracking note.
    run bash -c "cd \"$PROJECT_ROOT\" && bash tools/check-no-swallowed-jq.sh"
    [[ "$status" -eq 0 ]]
}

@test "scanner: --quiet suppresses listing but keeps exit code (SW-11)" {
    cat > "$FIX_DIR/bad.sh" <<'EOF'
#!/usr/bin/env bash
count=$(echo "$payload" | jq '.findings | length' 2>/dev/null || echo "0")
EOF
    run bash "$SCANNER" --root "$FIX_DIR" --quiet
    [[ "$status" -eq 1 ]]
    [[ -z "$output" ]]
}

@test "scanner: default mode catches extensionless red-team script (SW-12, DISS-001)" {
    # The red-team glob must be extension-agnostic: an extensionless
    # gate-critical script (bash shebang) is auto-enforced in DEFAULT mode,
    # not just under --root. _is_script decides scriptness, not the glob.
    mkdir -p "$BATS_TEST_TMPDIR/repo/.claude/scripts"
    cat > "$BATS_TEST_TMPDIR/repo/.claude/scripts/red-team-runner" <<'EOF'
#!/usr/bin/env bash
count=$(jq '.n' "$f" 2>/dev/null || echo "0")
EOF
    run bash -c "cd \"$BATS_TEST_TMPDIR/repo\" && bash \"$SCANNER\""
    [[ "$status" -eq 1 ]]
    [[ "$output" == *"red-team-runner:2"* ]]
}

@test "scanner: default mode skips non-script red-team-* files (SW-13)" {
    # Companion to SW-12: the widened glob must not flag prose files that
    # happen to share the red-team- prefix.
    mkdir -p "$BATS_TEST_TMPDIR/repo2/.claude/scripts"
    cat > "$BATS_TEST_TMPDIR/repo2/.claude/scripts/red-team-notes.md" <<'EOF'
count=$(jq '.n' "$f" 2>/dev/null || echo "0")
EOF
    # Provide one clean enforced file so found_any guard passes
    cat > "$BATS_TEST_TMPDIR/repo2/.claude/scripts/red-team-clean.sh" <<'EOF'
#!/usr/bin/env bash
true
EOF
    run bash -c "cd \"$BATS_TEST_TMPDIR/repo2\" && bash \"$SCANNER\""
    [[ "$status" -eq 0 ]]
}
