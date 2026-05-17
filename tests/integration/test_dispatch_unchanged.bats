#!/usr/bin/env bats
# cycle-112 Sprint 1 (#166) T1.8 — NFR-Compat-1 smoke gate.
#
# AC: this sprint MUST NOT modify the dispatch path. The model-economy
# roll-up reads pre-existing MODELINV envelopes; it does not produce them.
#
# Files this test guards:
#   - .claude/scripts/model-adapter.sh         (legacy dispatch entrypoint)
#   - .claude/adapters/loa_cheval/providers/   (every provider adapter)
#   - .claude/adapters/loa_cheval/routing/     (fallback / chain-walk)
#   - .claude/adapters/loa_cheval/audit/       (MODELINV writer is here)
#
# Note: SDD §5.1 originally listed `.claude/adapters/loa_cheval/cheval.py`
# but that file does not exist in this branch — adapter is composed across
# `routing/` + `providers/` + `audit_envelope.py`. The test covers the
# actual dispatch surface.

setup() {
    export PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    cd "$PROJECT_ROOT"
}

# Determine the base branch to diff against. Default is `main`; respect an
# override env-var so CI matrix jobs and PR checks can point at the correct
# merge base (e.g., `origin/main` when running in a detached checkout).
_base_ref() {
    echo "${LOA_NFR_COMPAT_BASE_REF:-main}"
}

# Run git diff and emit only the changed file list, filtered to paths that
# should NOT have changed for this sprint.
_dispatch_diff() {
    local base="$1"
    git diff --name-only "$base"...HEAD -- \
        .claude/scripts/model-adapter.sh \
        .claude/adapters/loa_cheval/providers/ \
        .claude/adapters/loa_cheval/routing/ \
        .claude/adapters/loa_cheval/audit/ \
        .claude/adapters/loa_cheval/audit_envelope.py \
        2>/dev/null
}

@test "T1.8.compat: model-adapter.sh unchanged from main" {
    base="$(_base_ref)"
    if ! git rev-parse --verify "$base" >/dev/null 2>&1; then
        skip "base ref '$base' not available in this checkout"
    fi
    run git diff --name-only "$base"...HEAD -- .claude/scripts/model-adapter.sh
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "T1.8.compat: loa_cheval/providers/ unchanged from main" {
    base="$(_base_ref)"
    if ! git rev-parse --verify "$base" >/dev/null 2>&1; then
        skip "base ref '$base' not available in this checkout"
    fi
    run git diff --name-only "$base"...HEAD -- .claude/adapters/loa_cheval/providers/
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "T1.8.compat: loa_cheval/routing/ unchanged from main" {
    base="$(_base_ref)"
    if ! git rev-parse --verify "$base" >/dev/null 2>&1; then
        skip "base ref '$base' not available in this checkout"
    fi
    run git diff --name-only "$base"...HEAD -- .claude/adapters/loa_cheval/routing/
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "T1.8.compat: MODELINV writer (audit_envelope.py + audit/) unchanged from main" {
    base="$(_base_ref)"
    if ! git rev-parse --verify "$base" >/dev/null 2>&1; then
        skip "base ref '$base' not available in this checkout"
    fi
    run git diff --name-only "$base"...HEAD -- \
        .claude/adapters/loa_cheval/audit/ \
        .claude/adapters/loa_cheval/audit_envelope.py
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "T1.8.compat: omnibus dispatch-path diff is empty" {
    base="$(_base_ref)"
    if ! git rev-parse --verify "$base" >/dev/null 2>&1; then
        skip "base ref '$base' not available in this checkout"
    fi
    changed="$(_dispatch_diff "$base")"
    if [ -n "$changed" ]; then
        echo "NFR-Compat-1 VIOLATION: dispatch-path files changed:" >&2
        echo "$changed" >&2
        false
    fi
}

# Smoke: economy.py / model-economy-roll-up.sh / schema DO exist on disk.
# This is a positive control: if it fails, the sprint deliverables are
# missing — either the branch is wrong or the smoke test logic is broken.
@test "T1.8.compat: positive control — sprint deliverables exist on disk" {
    [ -f .claude/adapters/loa_cheval/economy.py ]
    [ -f tools/model-economy-roll-up.sh ]
    [ -f .claude/data/schemas/model-economy-rollup.schema.json ]
}
