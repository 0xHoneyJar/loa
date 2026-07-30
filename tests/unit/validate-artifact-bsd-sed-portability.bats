#!/usr/bin/env bats
# =============================================================================
# validate-artifact-bsd-sed-portability.bats — cycle-123 T2.1 (#1216)
# =============================================================================
# `\s` is a GNU regex shorthand. POSIX BRE/ERE — which BSD sed and a BSD grep
# without REG_ENHANCED implement — treat `\s` as a literal 's'.
#
# Observed on macOS: the bug-triage validator REJECTS ITS OWN SHIPPED TEMPLATE.
# BSD sed fails to strip the Markdown prefix, so $bug_id becomes the whole line
# `- **bug_id**: <id>`, which cascades into an ID-grammar violation plus a
# bogus `.run/bugs/- **bug_id**: .../state.json` lookup. Under a BSD grep the
# selector misses entirely and the validator reports "no '**bug_id**:' line
# found" against a file that plainly contains one.
#
# Each case runs the REAL validator under BSD-semantics shims on a masked PATH.
# Per Ground rule 6 every shim carries a faithfulness positive control: if the
# shim does not itself reproduce the defect, the suite proves nothing.
# =============================================================================

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    VALIDATOR="$PROJECT_ROOT/.claude/scripts/validate-artifact.sh"
    SHIM_DIR="$BATS_TEST_TMPDIR/shim"
    WORK_DIR="$BATS_TEST_TMPDIR/work"
    mkdir -p "$SHIM_DIR" "$WORK_DIR"

    REAL_SED=$(command -v sed)
    REAL_GREP=$(command -v grep)
    export REAL_SED REAL_GREP

    # Hermetic PROJECT_ROOT so the validator's other legitimate checks (the
    # sibling state.json) are satisfied by the fixture rather than by the real
    # repo — the only variable under test is BSD-vs-GNU regex behavior.
    export FAKE_ROOT="$WORK_DIR/root"
    mkdir -p "$FAKE_ROOT/.run/bugs/20260730-a1b2c3"
    printf '{"schema_version": 1, "bug_id": "20260730-a1b2c3"}\n' \
        > "$FAKE_ROOT/.run/bugs/20260730-a1b2c3/state.json"

    # A triage artifact in the shipped template's shape.
    TRIAGE="$WORK_DIR/triage.md"
    cat > "$TRIAGE" <<'MD'
# Bug Triage

- **bug_id**: 20260730-a1b2c3
- **severity**: medium
- **status**: triaged

## Reproduction
Steps here.
MD
}

teardown() {
    cd /
    rm -rf "$BATS_TEST_TMPDIR/shim" "$BATS_TEST_TMPDIR/work"
}

skip_if_deps_missing() {
    command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

# BSD sed: POSIX ERE only — `\s` matches a literal 's', never whitespace.
_install_bsd_sed_shim() {
    cat > "$SHIM_DIR/sed" <<'SHIM'
#!/usr/bin/env bash
# Rewrite GNU-only \s into something that cannot match whitespace, modelling
# POSIX ERE where \s is an ordinary 's'.
args=()
for a in "$@"; do
    args+=("${a//\\s/s}")
done
exec "$REAL_SED" "${args[@]}"
SHIM
    chmod +x "$SHIM_DIR/sed"
}

# BSD grep without REG_ENHANCED: same treatment for the selector.
_install_bsd_grep_shim() {
    cat > "$SHIM_DIR/grep" <<'SHIM'
#!/usr/bin/env bash
args=()
for a in "$@"; do
    args+=("${a//\\s/s}")
done
exec "$REAL_GREP" "${args[@]}"
SHIM
    chmod +x "$SHIM_DIR/grep"
}

@test "T2.1 AC-1: no GNU \\s shorthand remains in validate-artifact.sh" {
    run bash -c "grep -c -F '\\s' '$VALIDATOR' || true"
    [[ "$output" == "0" ]] || {
        echo "expected 0 occurrences of \\s; got: $output"
        return 1
    }
}

@test "T2.1 AC-2: validator accepts the shipped template under a BSD sed shim" {
    skip_if_deps_missing
    _install_bsd_sed_shim

    run env PATH="$SHIM_DIR:$PATH" PROJECT_ROOT="$FAKE_ROOT" bash "$VALIDATOR" --type bug-triage --file "$TRIAGE" --json
    [[ "$status" -eq 0 ]] || {
        echo "expected exit 0 under BSD sed; got $status"
        echo "output: $output"
        return 1
    }
    local violations
    violations=$(echo "$output" | jq -r '.violations | length' 2>/dev/null || echo "parse-error")
    [[ "$violations" == "0" ]] || {
        echo "expected zero violations; got $violations — $output"
        return 1
    }
}

@test "T2.1 AC-3: no bogus 'no bug_id line found' under a BSD grep shim" {
    skip_if_deps_missing
    _install_bsd_grep_shim

    run env PATH="$SHIM_DIR:$PATH" PROJECT_ROOT="$FAKE_ROOT" bash "$VALIDATOR" --type bug-triage --file "$TRIAGE" --json
    [[ ! "$output" == *"no '**bug_id**:' line found"* ]] || {
        echo "selector missed a line that exists: $output"
        return 1
    }
}

@test "T2.1 AC-4: shim faithfulness — raw BSD sed still fails to strip the prefix" {
    _install_bsd_sed_shim

    local line stripped
    line='- **bug_id**: 20260730-a1b2c3'
    stripped=$(printf '%s\n' "$line" \
        | env PATH="$SHIM_DIR:$PATH" REAL_SED="$REAL_SED" \
          sed -E 's/^\s*-\s*\*\*bug_id\*\*:\s*//')

    # Under the shim the GNU pattern cannot match, so the line survives whole.
    [[ "$stripped" == "$line" ]] || {
        echo "shim does not model the BSD defect (stripped='$stripped') — this suite would prove nothing"
        return 1
    }
}

@test "T2.1 AC-5: POSIX class works where the GNU shorthand did not" {
    _install_bsd_sed_shim

    local line stripped
    line='- **bug_id**: 20260730-a1b2c3'
    stripped=$(printf '%s\n' "$line" \
        | env PATH="$SHIM_DIR:$PATH" REAL_SED="$REAL_SED" \
          sed -E 's/^[[:space:]]*-[[:space:]]*\*\*bug_id\*\*:[[:space:]]*//')

    [[ "$stripped" == "20260730-a1b2c3" ]] || {
        echo "expected bare id; got '$stripped'"
        return 1
    }
}
