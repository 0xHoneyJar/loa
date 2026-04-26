#!/usr/bin/env bats
# =============================================================================
# spiral-pre-check-implementation-evidence.bats — cycle-092 Sprint 2 (#600)
# =============================================================================
# Validates the pre-review artifact-coverage evidence gate:
# - _parse_sprint_paths extracts paths from sprint.md formats observed in
#   cycles 082/091/092 (backtick-wrapped checkboxes + bare prefixed paths)
# - _parse_sprint_paths scopes to `## Sprint N: ... ### Deliverables` when
#   sprint_id arg is provided
# - _pre_check_implementation_evidence returns 1 with diagnostic on missing
#   paths, 0 on happy path
# - Hermetic regression: cycle-091 scenario (sprint.md names .svelte files,
#   commit has only backend/tests) → IMPL_EVIDENCE_MISSING with .svelte list
# - Advisory IMPL_EVIDENCE_TRIVIAL for present-but-small/stub files
# =============================================================================

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export EVIDENCE_SH="$PROJECT_ROOT/.claude/scripts/spiral-evidence.sh"
    export TEST_DIR="$BATS_TEST_TMPDIR/spiral-evidence-gate-test"
    mkdir -p "$TEST_DIR"
}

teardown() {
    [[ -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# =========================================================================
# EG-T1: _parse_sprint_paths — format handling
# =========================================================================

@test "parser extracts backtick-wrapped paths from sprint.md deliverables" {
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: Test sprint

### Deliverables
- [ ] `src/lib/foo.ts` — foo module
- [ ] `tests/unit/foo.test.ts` — foo tests
- [ ] `.claude/scripts/helper.sh` — helper script
EOF
    run bash -c "source '$EVIDENCE_SH'; _parse_sprint_paths '$TEST_DIR/sprint.md' sprint-1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"src/lib/foo.ts"* ]]
    [[ "$output" == *"tests/unit/foo.test.ts"* ]]
    [[ "$output" == *".claude/scripts/helper.sh"* ]]
}

@test "parser extracts bare prefixed paths (code-block listings)" {
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: Test

### Deliverables
Deliverables for Sprint 1 include:

    src/lib/game/fsm.ts
    src/routes/page.svelte
    tests/unit/fsm.test.ts
EOF
    run bash -c "source '$EVIDENCE_SH'; _parse_sprint_paths '$TEST_DIR/sprint.md' sprint-1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"src/lib/game/fsm.ts"* ]]
    [[ "$output" == *"src/routes/page.svelte"* ]]
    [[ "$output" == *"tests/unit/fsm.test.ts"* ]]
}

@test "parser excludes bare filename prose (no slash in path)" {
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: Test

### Deliverables
- [ ] `src/lib/foo.ts` — Following the `helper.sh` pattern from `config.yaml`.
EOF
    run bash -c "source '$EVIDENCE_SH'; _parse_sprint_paths '$TEST_DIR/sprint.md' sprint-1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"src/lib/foo.ts"* ]]
    # Bare filenames `helper.sh`, `config.yaml` should NOT appear
    [[ "$output" != *$'\nhelper.sh\n'* ]]
    [[ "$output" != *$'\nconfig.yaml\n'* ]]
}

@test "parser dedupes paths mentioned multiple times" {
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: Test

### Deliverables
- [ ] `src/lib/foo.ts` — foo module
- [ ] `src/lib/foo.ts` — mentioned twice, should dedupe
EOF
    run bash -c "source '$EVIDENCE_SH'; _parse_sprint_paths '$TEST_DIR/sprint.md' sprint-1 | wc -l"
    [ "$status" -eq 0 ]
    [[ "${output// /}" == "1" ]]
}

@test "parser returns 1 when sprint.md is missing" {
    run bash -c "source '$EVIDENCE_SH'; _parse_sprint_paths '$TEST_DIR/nonexistent.md' sprint-1"
    [ "$status" -eq 1 ]
}

# =========================================================================
# EG-T2: _parse_sprint_paths — sprint_id scoping
# =========================================================================

@test "parser scopes to requested sprint_id (excludes other sprints' paths)" {
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: First

### Deliverables
- [ ] `src/sprint1-only.ts` — only Sprint 1

## Sprint 2: Second

### Deliverables
- [ ] `src/sprint2-only.ts` — only Sprint 2
EOF
    run bash -c "source '$EVIDENCE_SH'; _parse_sprint_paths '$TEST_DIR/sprint.md' sprint-1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"src/sprint1-only.ts"* ]]
    [[ "$output" != *"sprint2-only"* ]]
}

@test "parser scopes to ### Deliverables subsection (excludes Technical Tasks prose)" {
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: Test

### Deliverables
- [ ] `src/real-deliverable.ts` — actual output

### Technical Tasks
- Task 1.1: follow the `src/example-reference.ts` pattern (reference only)

### Risks
| Risk | Mitigation |
| Breaking `src/fragile-module.ts` | tests |
EOF
    run bash -c "source '$EVIDENCE_SH'; _parse_sprint_paths '$TEST_DIR/sprint.md' sprint-1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"src/real-deliverable.ts"* ]]
    [[ "$output" != *"src/example-reference.ts"* ]]
    [[ "$output" != *"src/fragile-module.ts"* ]]
}

@test "parser without sprint_id parses whole file (backward compat with /spiral flow)" {
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: First
### Deliverables
- [ ] `src/one.ts`

## Sprint 2: Second
### Deliverables
- [ ] `src/two.ts`
EOF
    run bash -c "source '$EVIDENCE_SH'; _parse_sprint_paths '$TEST_DIR/sprint.md'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"src/one.ts"* ]]
    [[ "$output" == *"src/two.ts"* ]]
}

# =========================================================================
# EG-T3: _pre_check_implementation_evidence — happy path
# =========================================================================

@test "happy path: all enumerated paths exist with content — returns 0" {
    mkdir -p "$TEST_DIR/src/lib"
    # Create files with ≥20 lines so they don't trigger trivial detection
    for i in $(seq 1 25); do echo "line $i" >> "$TEST_DIR/src/lib/foo.ts"; done
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: Test
### Deliverables
- [ ] `src/lib/foo.ts` — test deliverable
EOF
    run bash -c "cd '$TEST_DIR' && source '$EVIDENCE_SH' && _pre_check_implementation_evidence sprint.md sprint-1"
    [ "$status" -eq 0 ]
}

# =========================================================================
# EG-T4: _pre_check_implementation_evidence — missing paths
# =========================================================================

@test "missing path: returns 1 with IMPL_EVIDENCE_MISSING diagnostic" {
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: Test
### Deliverables
- [ ] `src/lib/nonexistent.ts` — will not be produced
EOF
    run bash -c "cd '$TEST_DIR' && source '$EVIDENCE_SH' && _pre_check_implementation_evidence sprint.md sprint-1 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"IMPL_EVIDENCE_MISSING"* ]]
    [[ "$output" == *"src/lib/nonexistent.ts"* ]]
    [[ "$output" == *"1 sprint-plan paths not produced"* ]]
}

@test "empty file: returns 1 (test -s treats zero bytes as missing)" {
    mkdir -p "$TEST_DIR/src/lib"
    touch "$TEST_DIR/src/lib/empty.ts"
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: Test
### Deliverables
- [ ] `src/lib/empty.ts` — empty stub
EOF
    run bash -c "cd '$TEST_DIR' && source '$EVIDENCE_SH' && _pre_check_implementation_evidence sprint.md sprint-1 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"IMPL_EVIDENCE_MISSING"* ]]
    [[ "$output" == *"src/lib/empty.ts"* ]]
}

@test "multiple missing paths: diagnostic lists all comma-separated" {
    mkdir -p "$TEST_DIR/src/lib"
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: Test
### Deliverables
- [ ] `src/lib/first.ts` — missing
- [ ] `src/lib/second.ts` — also missing
- [ ] `src/lib/third.ts` — also missing
EOF
    run bash -c "cd '$TEST_DIR' && source '$EVIDENCE_SH' && _pre_check_implementation_evidence sprint.md sprint-1 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"3 sprint-plan paths not produced"* ]]
    [[ "$output" == *"src/lib/first.ts"* ]]
    [[ "$output" == *"src/lib/second.ts"* ]]
    [[ "$output" == *"src/lib/third.ts"* ]]
}

# =========================================================================
# EG-T5: _pre_check_implementation_evidence — advisory trivial detection
# =========================================================================

@test "trivial file (<20 lines): emits IMPL_EVIDENCE_TRIVIAL advisory but returns 0" {
    mkdir -p "$TEST_DIR/src/lib"
    printf 'one\ntwo\nthree\n' > "$TEST_DIR/src/lib/stub.ts"
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: Test
### Deliverables
- [ ] `src/lib/stub.ts` — too small
EOF
    run bash -c "cd '$TEST_DIR' && source '$EVIDENCE_SH' && _pre_check_implementation_evidence sprint.md sprint-1 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"IMPL_EVIDENCE_TRIVIAL"* ]]
    [[ "$output" == *"src/lib/stub.ts"* ]]
    [[ "$output" == *"paths below content threshold"* ]]
}

@test "empty <script> tag Svelte stub: emits IMPL_EVIDENCE_TRIVIAL" {
    mkdir -p "$TEST_DIR/src/lib"
    # Iter-5 BB e98e4f50 fix: file written once. Previous version wrote a
    # multi-line <script>...</script> form, then immediately overwrote it
    # with a single-line form — first heredoc was dead code.
    # The single-line `<script></script>` form is what the stub-regex
    # triggers on, so >=20 lines is satisfied via the placeholder padding.
    {
        echo "<script></script>"
        for i in $(seq 1 25); do echo "<!-- placeholder $i -->"; done
    } > "$TEST_DIR/src/lib/Stub.svelte"
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: Test
### Deliverables
- [ ] `src/lib/Stub.svelte` — empty component
EOF
    run bash -c "cd '$TEST_DIR' && source '$EVIDENCE_SH' && _pre_check_implementation_evidence sprint.md sprint-1 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"IMPL_EVIDENCE_TRIVIAL"* ]]
}

# =========================================================================
# EG-T6: hermetic regression — cycle-091 scenario
# =========================================================================
# Reproduce issue #600's original scenario: sprint.md names a Svelte scene
# and a route page, IMPL subprocess commits only backend+test files, omits
# the visible surfaces.

@test "cycle-091 regression: backend-only commit against scene+route deliverables → IMPL_EVIDENCE_MISSING" {
    # Commit layout mimics cycle-091's aaa278b3: backend + tests present,
    # TheReliquaryScene.svelte + +page.svelte absent.
    mkdir -p "$TEST_DIR/src/lib/game/reliquary" "$TEST_DIR/src/lib/scenes/tests" "$TEST_DIR/src/lib/scenes" "$TEST_DIR/src/routes/(rooms)/reliquary"
    # Backend files (present — cycle-091 shipped these)
    for f in fsm ceremony-registry resolve-kaironic interrupt-policy types; do
        for i in $(seq 1 30); do echo "line $i" >> "$TEST_DIR/src/lib/game/reliquary/$f.ts"; done
    done
    for i in $(seq 1 30); do echo "test line $i" >> "$TEST_DIR/src/lib/scenes/tests/reliquary-mount-parity.test.ts"; done
    # Visible-surface files ABSENT (cycle-091 shortcircuit): Reliquary.svelte + +page.svelte

    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 8: TheReliquaryScene + visible surface

### Deliverables
- [ ] `src/lib/game/reliquary/fsm.ts` — state machine
- [ ] `src/lib/game/reliquary/ceremony-registry.ts`
- [ ] `src/lib/game/reliquary/resolve-kaironic.ts`
- [ ] `src/lib/game/reliquary/interrupt-policy.ts`
- [ ] `src/lib/game/reliquary/types.ts`
- [ ] `src/lib/scenes/Reliquary.svelte` — VISIBLE SURFACE (must not be skipped)
- [ ] `src/lib/scenes/tests/reliquary-mount-parity.test.ts`
- [ ] `src/routes/(rooms)/reliquary/+page.svelte` — ROUTE ENTRY (must not be skipped)
EOF
    run bash -c "cd '$TEST_DIR' && source '$EVIDENCE_SH' && _pre_check_implementation_evidence sprint.md sprint-8 2>&1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"IMPL_EVIDENCE_MISSING"* ]]
    [[ "$output" == *"2 sprint-plan paths not produced"* ]]
    [[ "$output" == *"Reliquary.svelte"* ]]
    [[ "$output" == *"+page.svelte"* ]]
}

# =========================================================================
# EG-T7: integration with grammar spec
# =========================================================================

@test "IMPL_EVIDENCE_MISSING log line matches grammar spec regex" {
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: Test
### Deliverables
- [ ] `src/missing-path-a.ts`
- [ ] `src/missing-path-b.ts`
EOF
    run bash -c "cd '$TEST_DIR' && source '$EVIDENCE_SH' && _pre_check_implementation_evidence sprint.md sprint-1 2>&1"
    [ "$status" -eq 1 ]
    # Grammar spec reserves: ^\[harness\] IMPL_EVIDENCE_MISSING — \d+ sprint-plan paths not produced: \S+
    [[ "$output" =~ \[harness\]\ IMPL_EVIDENCE_MISSING\ —\ [0-9]+\ sprint-plan\ paths\ not\ produced: ]]
}

@test "IMPL_EVIDENCE_TRIVIAL log line matches grammar spec regex" {
    mkdir -p "$TEST_DIR/src"
    printf 'one\ntwo\nthree\n' > "$TEST_DIR/src/stub.ts"
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: Test
### Deliverables
- [ ] `src/stub.ts` — trivially small
EOF
    run bash -c "cd '$TEST_DIR' && source '$EVIDENCE_SH' && _pre_check_implementation_evidence sprint.md sprint-1 2>&1"
    [ "$status" -eq 0 ]
    # Grammar spec reserves: ^\[harness\] IMPL_EVIDENCE_TRIVIAL — \d+ paths below content threshold: \S+
    [[ "$output" =~ \[harness\]\ IMPL_EVIDENCE_TRIVIAL\ —\ [0-9]+\ paths\ below\ content\ threshold: ]]
}

# =========================================================================
# EG-T8: no enumerated paths = non-blocking pass
# =========================================================================

@test "empty deliverables section: passes silently (no enumerated paths = no evidence to check)" {
    cat > "$TEST_DIR/sprint.md" <<'EOF'
## Sprint 1: Docs-only

### Deliverables
This sprint only updates existing documentation in-place; no new files.
EOF
    run bash -c "cd '$TEST_DIR' && source '$EVIDENCE_SH' && _pre_check_implementation_evidence sprint.md sprint-1 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" != *"IMPL_EVIDENCE_MISSING"* ]]
}

@test "missing sprint.md: passes (upstream concern, not evidence gap)" {
    run bash -c "cd '$TEST_DIR' && source '$EVIDENCE_SH' && _pre_check_implementation_evidence '$TEST_DIR/never.md' sprint-1 2>&1"
    [ "$status" -eq 0 ]
    [[ "$output" != *"IMPL_EVIDENCE_MISSING"* ]]
}
