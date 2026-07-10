#!/usr/bin/env bats
# =============================================================================
# installer-safety.bats — #1162 installer trust-root / filesystem-safety gate
# =============================================================================
# Enforces check-installer-safety.sh (exit 1 on findings) under the Shell
# Tests gate, with regression fixtures proving the checker catches each of the
# three audited pattern classes, plus behavioral tests of the actual guards.

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    CHECKER="$PROJECT_ROOT/.claude/scripts/check-installer-safety.sh"
    FIXDIR="$BATS_TEST_TMPDIR/fixtures"
    mkdir -p "$FIXDIR"
}

# --- Enforcement: the live installers must be clean --------------------------

@test "IS-1: check-installer-safety passes on the live mount scripts" {
    run bash "$CHECKER"
    [ "$status" -eq 0 ]
    [[ "$output" == *"clean"* ]]
}

# --- Regression fixtures: each audited pattern class is CAUGHT ---------------

@test "IS-2: checker catches echo -e output helper (fragile output pattern)" {
    cat > "$FIXDIR/p1.sh" <<'EOF'
#!/usr/bin/env bash
log() { echo -e "${GREEN}[x]${NC} $*"; }
EOF
    run bash "$CHECKER" "$FIXDIR/p1.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"echo -e"* ]]
}

@test "IS-3: checker catches unguarded option-operand read in CLI parser" {
    cat > "$FIXDIR/p2.sh" <<'EOF'
#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do
  case $1 in
    --branch)
      LOA_BRANCH="$2"
      shift 2
      ;;
  esac
done
EOF
    run bash "$CHECKER" "$FIXDIR/p2.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"unguarded option operand"* ]]
}

@test "IS-4: checker catches bare-prefix repo-boundary comparison" {
    cat > "$FIXDIR/p3.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "$resolved_target" != "$repo_root"* ]]; then
  exit 1
fi
EOF
    run bash "$CHECKER" "$FIXDIR/p3.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"bare-prefix boundary"* ]]
}

@test "IS-5: checker accepts the guarded/printf-safe forms (no false positives)" {
    cat > "$FIXDIR/ok.sh" <<'EOF'
#!/usr/bin/env bash
log() { printf '%b[x]%b %s\n' "$GREEN" "$NC" "$*"; }
require_operand() { [[ -n "${2:-}" ]] || exit 1; }
while [[ $# -gt 0 ]]; do
  case $1 in
    --branch)
      require_operand "$1" "${2:-}"
      LOA_BRANCH="$2"
      shift 2
      ;;
  esac
done
if [[ "$resolved_target" != "$repo_root" && "$resolved_target" != "$repo_root"/* ]]; then
  exit 1
fi
EOF
    run bash "$CHECKER" "$FIXDIR/ok.sh"
    [ "$status" -eq 0 ]
}

@test "IS-6: checker exits 2 when a target file is missing" {
    run bash "$CHECKER" "$FIXDIR/does-not-exist.sh"
    [ "$status" -eq 2 ]
}

# --- Behavioral: the installer guards actually fire --------------------------

@test "IS-7: mount-submodule --branch with missing operand fails loudly" {
    run bash "$PROJECT_ROOT/.claude/scripts/mount-submodule.sh" --source-only --branch
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires a value"* ]]
}

@test "IS-8: mount-submodule --tag consuming a flag as operand fails loudly" {
    run bash "$PROJECT_ROOT/.claude/scripts/mount-submodule.sh" --source-only --tag --force
    [ "$status" -ne 0 ]
    [[ "$output" == *"requires a value"* ]]
}

@test "IS-9: repo-boundary check rejects a sibling directory (/repo-evil vs /repo)" {
    # Reproduce the fixed comparison inline with the exact operands.
    repo_root="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$repo_root" "$BATS_TEST_TMPDIR/repo-evil"
    resolved_target="$BATS_TEST_TMPDIR/repo-evil/x"
    run bash -c '[[ "'"$resolved_target"'" != "'"$repo_root"'" && "'"$resolved_target"'" != "'"$repo_root"'"/* ]] && echo ESCAPES || echo INSIDE'
    [[ "$output" == "ESCAPES" ]]
    # ...and accepts a genuine inside path
    resolved_target="$repo_root/sub/file"
    run bash -c '[[ "'"$resolved_target"'" != "'"$repo_root"'" && "'"$resolved_target"'" != "'"$repo_root"'"/* ]] && echo ESCAPES || echo INSIDE'
    [[ "$output" == "INSIDE" ]]
}
