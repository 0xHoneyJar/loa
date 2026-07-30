#!/usr/bin/env bats
# Unit tests for the heredoc state machine in tools/check-no-swallowed-jq.sh.
#
# Scope: ONLY the heredoc-skip behavior added by PR #1167. The scanner's base
# matching contract (clean/flagged/suppression/shebang detection) is pinned by
# tests/integration/check-no-swallowed-jq.bats (SW-1..SW-9) — not repeated here.
#
# The fail-open classes pinned below were live on the PR's original head
# (review 2026-07-30): a heredoc opener misread on bit-shift arithmetic,
# quoted mentions, or an executed heredoc caused REAL violations to be
# silently skipped — the wrong direction for a KF-004/KF-015 tripwire.

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCANNER="$PROJECT_ROOT/tools/check-no-swallowed-jq.sh"
    [[ -x "$SCANNER" ]] || skip "scanner not executable: $SCANNER"
    FIXTURE_ROOT="$BATS_TEST_TMPDIR/fixture-root"
    mkdir -p "$FIXTURE_ROOT"
}

teardown() {
    rm -rf "$FIXTURE_ROOT"
}

@test "HD1: inert heredoc fixture text is not flagged (the false-positive class)" {
    cat > "$FIXTURE_ROOT/heredoc-fixture.bats" <<'SH'
#!/usr/bin/env bats
@test "plants a bad example" {
    cat > "$BATS_TEST_TMPDIR/bad.sh" <<'SCRIPT'
#!/usr/bin/env bash
count="$(jq -r '.count' report.json 2>/dev/null || echo 0)"
SCRIPT
    true
}
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 0 ]
}

@test "HD2: bit-shift arithmetic does not open a heredoc (flatline-error-handler.sh:202 class)" {
    cat > "$FIXTURE_ROOT/backoff.sh" <<'SH'
#!/usr/bin/env bash
delay=$((base_delay * (1 << attempt)))
sleep "$delay"
count="$(jq -r '.count' report.json 2>/dev/null || echo 0)"
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"backoff.sh"* ]]
}

@test "HD3: bare arithmetic command bit-shift does not open a heredoc" {
    cat > "$FIXTURE_ROOT/arith.sh" <<'SH'
#!/usr/bin/env bash
(( mask = 1 << width ))
count="$(jq -r '.count' report.json || echo 0)"
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"arith.sh"* ]]
}

@test "HD4: quoted << mention does not open a heredoc" {
    cat > "$FIXTURE_ROOT/mention.sh" <<'SH'
#!/usr/bin/env bash
echo "use <<EOF here for the template"
count="$(jq -r '.count' report.json || echo 0)"
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"mention.sh"* ]]
}

@test "HD5: here-string does not open a heredoc" {
    cat > "$FIXTURE_ROOT/herestring.sh" <<'SH'
#!/usr/bin/env bash
read -r first <<< "$RAW_INPUT"
count="$(jq -r '.count' report.json || echo 0)"
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"herestring.sh"* ]]
}

@test "HD6: executed heredoc body (bash <<'SCRIPT') IS scanned" {
    cat > "$FIXTURE_ROOT/executed.sh" <<'SH'
#!/usr/bin/env bash
bash <<'SCRIPT'
count="$(jq -r '.count' report.json 2>/dev/null || echo 0)"
SCRIPT
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"executed.sh"* ]]
}

@test "HD7: heredoc piped into an interpreter (cat <<EOF | bash) IS scanned" {
    cat > "$FIXTURE_ROOT/piped.sh" <<'SH'
#!/usr/bin/env bash
cat <<'EOF' | bash
count="$(jq -r '.count' report.json || echo 0)"
EOF
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"piped.sh"* ]]
}

@test "HD8: scanning resumes after an inert heredoc terminator" {
    cat > "$FIXTURE_ROOT/after.sh" <<'SH'
#!/usr/bin/env bash
cat > /tmp/fixture <<'EOF'
this body is data: jq . x.json || echo skipped-ok
EOF
count="$(jq -r '.count' report.json || echo 0)"
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"after.sh:5:"* ]]
    [[ "$output" != *"skipped-ok"* ]]
}

@test "HD10: unquoted heredoc body IS scanned (\$() substitutions execute in it)" {
    cat > "$FIXTURE_ROOT/unquoted.sh" <<'SH'
#!/usr/bin/env bash
cat << EOF
  "total": $(br list --json 2>/dev/null | jq 'length' || echo "0")
EOF
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unquoted.sh"* ]]
}

@test "HD9: heredoc opener on a suppression-marker line still registers" {
    cat > "$FIXTURE_ROOT/marker-open.sh" <<'SH'
#!/usr/bin/env bash
cat > /tmp/fixture <<'EOF' # check-no-swallowed-jq: ok (fixture body below)
data line: jq . x.json || echo fixture-text
EOF
count="$(jq -r '.count' report.json || echo 0)"
SH
    run "$SCANNER" --root "$FIXTURE_ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"marker-open.sh:5:"* ]]
    [[ "$output" != *"fixture-text"* ]]
}

# =============================================================================
# YQ1/YQ2 — non-vacuity of the construct-index-gen.sh enforcement (#1065)
# =============================================================================
# #1065 asked only for construct-index-gen.sh to join ENFORCED_FILES. That alone
# passes for the wrong reason: every swallow site in that file is a yq call, and
# the matcher only knew jq — a fence reporting safety it does not provide. YQ1
# pins that the scanner can actually SEE a yq swallow in that file when run in
# default (enforced-set) mode.

@test "YQ1: a fresh yq swallow in construct-index-gen.sh is FLAGGED in default mode (#1065)" {
    local fake_root="$BATS_TEST_TMPDIR/fake-root"
    mkdir -p "$fake_root/.claude/scripts"
    cp "$PROJECT_ROOT/.claude/scripts/construct-index-gen.sh" \
       "$fake_root/.claude/scripts/construct-index-gen.sh"
    # A regression of exactly the shape this task removed. The marker keeps the
    # fixture STRING from being read as a real site if this tree is ever scanned.
    local regression='sv=$(yq eval ".capabilities.schema_version" "$tmp_fm" 2>/dev/null || echo "0")'  # check-no-swallowed-jq: ok (fixture text, not an executed call)
    printf '%s\n' "$regression" >> "$fake_root/.claude/scripts/construct-index-gen.sh"

    cd "$fake_root"
    run "$SCANNER"
    [ "$status" -eq 1 ]
    [[ "$output" == *"construct-index-gen.sh"* ]]
}

@test "YQ2: the real enforced set — construct-index-gen.sh included — is clean (#1065)" {
    cd "$PROJECT_ROOT"
    run "$SCANNER"
    [ "$status" -eq 0 ]
    # Guard against a silently empty scan (the enforced-set glob resolving to
    # nothing would also exit 0 with a different message).
    [[ "$output" == *"no output-swallowing jq shapes on the enforced set"* ]]
    grep -q 'construct-index-gen\.sh' "$SCANNER"
}
