#!/usr/bin/env bash
# =============================================================================
# scaffold-post-merge-workflow.sh — single source of truth for #669 scaffold
# =============================================================================
# Bridgebuilder F2 + F6 (PR #671): the scaffold helper used to live in three
# places (mount-loa.sh, mount-submodule.sh, and an inline copy in
# tests/unit/mount-workflow-scaffold.bats), held together by a "keep in sync"
# comment. Three-way duplication is exactly the maintenance hazard the
# Bridgebuilder flagged — drift between test fixture and production passes
# tests while breaking users.
#
# This lib is the canonical implementation. Sourced by both installer
# scripts AND the test file so the test exercises the same code that runs
# in production. Pattern mirrors lib/portable-realpath.sh and
# lib/flatline-exit-classifier.sh.
#
# Usage (sourced):
#   source scaffold-post-merge-workflow.sh
#   scaffold_post_merge_workflow [source_path]
#
# Args:
#   $1 — optional absolute path to a workflow file. When empty/absent,
#        the helper falls through to `git checkout
#        $LOA_REMOTE_NAME/$LOA_BRANCH -- .github/workflows/post-merge.yml`.
#
# Behavior:
#   - Idempotent: if `.github/workflows/post-merge.yml` already exists,
#     preserves it (matches sync_optional_file semantics)
#   - Mode-agnostic: direct mode passes empty (uses git checkout fallback);
#     submodule mode passes the in-tree submodule path
#   - Always returns 0 (best-effort scaffold; never aborts the installer)
# =============================================================================

scaffold_post_merge_workflow() {
    local source_path="${1:-}"
    local target=".github/workflows/post-merge.yml"

    if [[ -f "$target" ]]; then
        # Idempotency: preserve user-customized workflow on re-mount
        return 0
    fi

    mkdir -p .github/workflows

    if [[ -n "$source_path" && -f "$source_path" ]]; then
        cp "$source_path" "$target"
        return 0
    fi

    # Fallback: git checkout from configured upstream (direct-install mode)
    if [[ -n "${LOA_REMOTE_NAME:-}" && -n "${LOA_BRANCH:-}" ]]; then
        git checkout "$LOA_REMOTE_NAME/$LOA_BRANCH" -- "$target" 2>/dev/null || true
    fi

    return 0
}
