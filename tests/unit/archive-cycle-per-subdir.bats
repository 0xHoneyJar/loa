#!/usr/bin/env bats
# =============================================================================
# archive-cycle-per-subdir.bats — cycle-104 Sprint 1 T1.8 — #848 coverage
# =============================================================================
# Pins the AC-1.1, AC-1.2 (partial), AC-1.4 behaviors of archive-cycle.sh
# under the per-cycle subdir convention introduced for cycles ≥098.
#
# Each test runs the real archive-cycle.sh against a hermetic mktemp
# grimoire tree so the project's own grimoires/loa/ is never touched.
# =============================================================================

setup() {
    export LOA_REPO_ROOT
    LOA_REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
    export SCRIPT="$LOA_REPO_ROOT/.claude/scripts/archive-cycle.sh"

    [[ -x "$SCRIPT" ]] || skip "archive-cycle.sh not found at $SCRIPT"
    [[ -f "$LOA_REPO_ROOT/.claude/scripts/bootstrap.sh" ]] || skip "bootstrap.sh missing"

    # Unset PROJECT_ROOT so bootstrap.sh detects from WORKDIR (not parent shell)
    unset PROJECT_ROOT 2>/dev/null || true

    # Hermetic working dir + git init so bootstrap.sh's PROJECT_ROOT
    # detection resolves to WORKDIR (not the enclosing real loa repo)
    export WORKDIR
    WORKDIR="$(mktemp -d)"
    cd "$WORKDIR"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"

    # Copy the script under test + its bootstrap dependency into WORKDIR
    # so it operates against the hermetic tree's PROJECT_ROOT.
    mkdir -p .claude/scripts
    cp "$LOA_REPO_ROOT/.claude/scripts/archive-cycle.sh" .claude/scripts/
    cp "$LOA_REPO_ROOT/.claude/scripts/bootstrap.sh" .claude/scripts/
    [[ -f "$LOA_REPO_ROOT/.claude/scripts/path-lib.sh" ]] && cp "$LOA_REPO_ROOT/.claude/scripts/path-lib.sh" .claude/scripts/
    SCRIPT="$WORKDIR/.claude/scripts/archive-cycle.sh"

    # Mirror the minimum layout archive-cycle.sh expects:
    mkdir -p grimoires/loa/archive
    mkdir -p grimoires/loa/cycles/cycle-104-multi-model-stabilization/{handoffs,a2a,flatline}
    mkdir -p grimoires/loa/cycles/cycle-103-provider-unification/handoffs
    mkdir -p grimoires/loa/a2a/compound  # legacy compound state

    # Modern per-cycle artifacts
    echo "# cycle-104 PRD" > grimoires/loa/cycles/cycle-104-multi-model-stabilization/prd.md
    echo "# cycle-104 SDD" > grimoires/loa/cycles/cycle-104-multi-model-stabilization/sdd.md
    echo "# cycle-104 sprint" > grimoires/loa/cycles/cycle-104-multi-model-stabilization/sprint.md
    echo "modern handoff" > grimoires/loa/cycles/cycle-104-multi-model-stabilization/handoffs/h1.md

    echo "# cycle-103 PRD" > grimoires/loa/cycles/cycle-103-provider-unification/prd.md
    echo "# cycle-103 SDD" > grimoires/loa/cycles/cycle-103-provider-unification/sdd.md
    echo "# cycle-103 sprint" > grimoires/loa/cycles/cycle-103-provider-unification/sprint.md
    echo "cycle-103 handoff" > grimoires/loa/cycles/cycle-103-provider-unification/handoffs/h1.md

    # Legacy root artifacts (for cycle-097 fallback test)
    echo "# legacy root PRD" > grimoires/loa/prd.md
    echo "# legacy root SDD" > grimoires/loa/sdd.md
    echo "# legacy root sprint" > grimoires/loa/sprint.md
    echo "legacy compound" > grimoires/loa/a2a/compound/c1.md

    # Synthetic ledger with three cycles spanning the layout transition
    cat > grimoires/loa/ledger.json <<'EOF'
{
  "schema_version": 1,
  "active_cycle": null,
  "cycles": [
    {
      "id": "cycle-097-legacy",
      "label": "Legacy root cycle",
      "status": "archived",
      "prd": "grimoires/loa/prd.md",
      "sdd": "grimoires/loa/sdd.md",
      "sprint_plan": "grimoires/loa/sprint.md"
    },
    {
      "id": "cycle-103-provider-unification",
      "label": "Provider unification",
      "status": "archived",
      "cycle_folder": "grimoires/loa/cycles/cycle-103-provider-unification/",
      "prd": "grimoires/loa/cycles/cycle-103-provider-unification/prd.md",
      "sdd": "grimoires/loa/cycles/cycle-103-provider-unification/sdd.md",
      "sprint_plan": "grimoires/loa/cycles/cycle-103-provider-unification/sprint.md"
    },
    {
      "id": "cycle-104-multi-model-stabilization",
      "label": "Multi-model stabilization",
      "status": "active",
      "prd": "grimoires/loa/cycles/cycle-104-multi-model-stabilization/prd.md",
      "sdd": "grimoires/loa/cycles/cycle-104-multi-model-stabilization/sdd.md",
      "sprint_plan": "grimoires/loa/cycles/cycle-104-multi-model-stabilization/sprint.md"
    }
  ]
}
EOF

    # Empty .loa.config.yaml so yq fallback hits the default RETENTION=5
    touch .loa.config.yaml
}

teardown() {
    [[ -n "${WORKDIR:-}" ]] && [[ -d "$WORKDIR" ]] && rm -rf "$WORKDIR"
}

# -------- AC-1.1: per-cycle-subdir resolution (modern, ≥098) --------

@test "AC-1.1: cycle-104 dry-run enumerates per-cycle subdir as artifact source" {
    run "$SCRIPT" --cycle 104 --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Cycle id: cycle-104-multi-model-stabilization"
    echo "$output" | grep -q "Artifact source:.*cycles/cycle-104-multi-model-stabilization"
    echo "$output" | grep -q "cycles/cycle-104-multi-model-stabilization/prd.md"
}

@test "AC-1.1: cycle-103 dry-run resolves via ledger cycle_folder field" {
    run "$SCRIPT" --cycle 103 --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "cycles/cycle-103-provider-unification/prd.md"
    echo "$output" | grep -q "cycles/cycle-103-provider-unification/handoffs/"
}

# -------- AC-1.2 (backward compat): legacy cycle ≤097 falls back to root --------

@test "AC-1.2: cycle-097 falls back to grimoire root (legacy layout)" {
    run "$SCRIPT" --cycle 97 --dry-run
    [ "$status" -eq 0 ]
    # When artifact_root resolves to the grimoire root, dry-run output
    # quotes the GRIMOIRE_DIR-prefixed paths (not cycles/cycle-097-*).
    echo "$output" | grep -q "Artifact source:.*grimoires/loa"
    [[ "$output" != *"cycles/cycle-097-legacy/prd.md"* ]]
    # The legacy a2a/compound copy path is mentioned
    echo "$output" | grep -q "a2a/compound/"
}

# -------- AC-1.4: modern cycle subdirs (handoffs/a2a/flatline) all copied --------

@test "AC-1.4: cycle-104 archive (non-dry-run) copies handoffs and a2a from per-cycle subdir" {
    run "$SCRIPT" --cycle 104 --retention 0
    [ "$status" -eq 0 ]

    local archive="grimoires/loa/archive/cycle-104-multi-model-stabilization"
    [[ -d "$archive" ]]
    [[ -f "$archive/prd.md" ]]
    [[ -f "$archive/sdd.md" ]]
    [[ -f "$archive/sprint.md" ]]
    [[ -f "$archive/ledger.json" ]]
    [[ -d "$archive/handoffs" ]]
    [[ -f "$archive/handoffs/h1.md" ]]
    [[ -d "$archive/a2a" ]]
    [[ -d "$archive/flatline" ]]
    # Legacy a2a/compound MUST NOT be copied for modern cycles
    [[ ! -d "$archive/compound" ]]
}

@test "AC-1.4 backward compat: cycle-097 archive includes legacy a2a/compound" {
    run "$SCRIPT" --cycle 97 --retention 0
    [ "$status" -eq 0 ]

    # Archive path follows ledger slug (cycle-097-legacy) when the cycle is
    # found in the ledger, regardless of legacy artifact source.
    local archive="grimoires/loa/archive/cycle-097-legacy"
    [[ -d "$archive" ]]
    [[ -f "$archive/prd.md" ]]
    grep -q "legacy root" "$archive/prd.md"
    [[ -d "$archive/compound" ]]  # legacy compound state copied
    [[ -f "$archive/compound/c1.md" ]]
}

# -------- Regression guard: dry-run exit code is 0 even when optional dirs are absent --------

@test "regression: dry-run exits 0 when flatline/ subdir absent" {
    rm -rf grimoires/loa/cycles/cycle-104-multi-model-stabilization/flatline
    run "$SCRIPT" --cycle 104 --dry-run
    [ "$status" -eq 0 ]
}
