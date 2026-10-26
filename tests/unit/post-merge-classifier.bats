#!/usr/bin/env bats
# =============================================================================
# post-merge-classifier.bats — Tests for classify-pr-type.sh (Issue #550)
# =============================================================================
# Sprint-bug-104. Validates the shared PR-type classifier that routes merged
# PRs into the Simple Release or Full Pipeline job in post-merge automation
# (or neither, for housekeeping merges: bd-nr5i6, cycle-135 C-4).

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export CLASSIFIER="$PROJECT_ROOT/.claude/scripts/classify-pr-type.sh"
}

# =========================================================================
# PCT-T1..PCT-T4: label-based routing (highest precedence)
# =========================================================================

@test "label 'cycle' routes to cycle regardless of title" {
    run "$CLASSIFIER" --title "random nonsense" --labels "cycle"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

@test "label 'Cycle' (case-insensitive) routes to cycle" {
    run "$CLASSIFIER" --title "unrelated" --labels "Cycle,v2"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

# =========================================================================
# PCT-T5..PCT-T10: title matching — the #550 defect class
# =========================================================================

@test "feat(models): with cycle-NNN suffix → cycle (#550 regression case)" {
    run "$CLASSIFIER" --title "feat(models): promote Opus 4.7 to top-review default (cycle-082)"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

@test "feat(bridge): with cycle-NNN suffix → cycle" {
    run "$CLASSIFIER" --title "feat(bridge): enrich kaironic review (cycle-053)"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

@test "feat(harness): with cycle-NNN → cycle" {
    run "$CLASSIFIER" --title "feat(harness): spiral orchestrator (cycle-071)"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

@test "feat(sprint-3): legacy prefix still matches → cycle" {
    run "$CLASSIFIER" --title "feat(sprint-3): task batch"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

@test "feat(cycle-042): explicit prefix matches → cycle" {
    run "$CLASSIFIER" --title "feat(cycle-042): mining runtime routing"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

@test "Run Mode: full autonomous run → cycle" {
    run "$CLASSIFIER" --title "Run Mode: autonomous sprint 3"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

# =========================================================================
# PCT-T-CASE: capitalized cycle-NNN token (#971 regression — PR #970 misroute)
# The merge subject "Cycle-114: ..." (capital C) was classified 'other' because
# rule #2 used case-sensitive grep, so the post-merge Full Pipeline was skipped.
# =========================================================================

@test "Cycle-114: capitalized leading token → cycle (#971 / PR #970)" {
    run "$CLASSIFIER" --title "Cycle-114: Harness Modernization for Opus 4.8 (#970)"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

@test "mid-title uppercase CYCLE-099 → cycle (#971 triangulation)" {
    run "$CLASSIFIER" --title "Some CYCLE-099 work in progress"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

# =========================================================================
# PCT-T11..PCT-T13: anti-false-positive (the bug's mirror image)
# =========================================================================

@test "feat: (bare, no cycle-NNN) does NOT match cycle — regression guard" {
    run "$CLASSIFIER" --title "feat: add login form"
    [ "$status" -eq 0 ]
    [ "$output" = "other" ]
}

@test "feat(auth): without cycle-NNN does NOT match cycle" {
    run "$CLASSIFIER" --title "feat(auth): implement OAuth flow"
    [ "$status" -eq 0 ]
    [ "$output" = "other" ]
}

@test "cycle-related word in prose (not cycle-NNN) does NOT match" {
    run "$CLASSIFIER" --title "refactor: break cycle dependency in auth module"
    [ "$status" -eq 0 ]
    [ "$output" = "other" ]
}

# =========================================================================
# PCT-T-MID-1: cycle-NNN in middle of title (Bridgebuilder DISPUTED finding)
# =========================================================================
# Triangulates the "anywhere" regex claim — start/middle/end must all match.

@test "cycle-NNN mid-title matches — triangulation" {
    run "$CLASSIFIER" --title "feat: implement cycle-099 features"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

@test "cycle-NNN with content after also matches" {
    run "$CLASSIFIER" --title "chore: cycle-042 release prep and final doc update"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

# =========================================================================
# PCT-T-BOUNDARY: word-boundary negative cases
# =========================================================================

@test "precycle-082 (no word boundary before 'cycle') does NOT match" {
    run "$CLASSIFIER" --title "feat: rebuild precycle-082 scaffold"
    [ "$status" -eq 0 ]
    [ "$output" = "other" ]
}

@test "cycle-abc (non-numeric suffix) does NOT match" {
    run "$CLASSIFIER" --title "feat: cycle-abc branch protection"
    [ "$status" -eq 0 ]
    [ "$output" = "other" ]
}

# =========================================================================
# PCT-T14..PCT-T16: bugfix routing
# =========================================================================

@test "fix: routes to bugfix" {
    run "$CLASSIFIER" --title "fix: null pointer in parser"
    [ "$status" -eq 0 ]
    [ "$output" = "bugfix" ]
}

@test "fix(auth): routes to bugfix" {
    run "$CLASSIFIER" --title "fix(auth): OAuth state validation"
    [ "$status" -eq 0 ]
    [ "$output" = "bugfix" ]
}

@test "fix(skills): with cycle-NNN routes to cycle (label precedes fix)" {
    run "$CLASSIFIER" --title "fix(skills): agent: Plan blocks Write (cycle-083)"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

# =========================================================================
# PCT-T17: default fallback
# =========================================================================

@test "unclassifiable title routes to other" {
    run "$CLASSIFIER" --title "random untyped PR"
    [ "$status" -eq 0 ]
    [ "$output" = "other" ]
}

@test "empty title routes to other" {
    run "$CLASSIFIER" --title ""
    [ "$status" -eq 0 ]
    [ "$output" = "other" ]
}

# =========================================================================
# PCT-T18: arg validation
# =========================================================================

@test "--title without value exits 2" {
    run "$CLASSIFIER" --title
    [ "$status" -eq 2 ]
}

@test "--labels without value exits 2" {
    run "$CLASSIFIER" --title "x" --labels
    [ "$status" -eq 2 ]
}

# =========================================================================
# PCT-T20: sourceable helper function
# =========================================================================

@test "function classify_pr_type is sourceable and callable" {
    run bash -c "source '$CLASSIFIER'; classify_pr_type 'feat(models): cycle-099' ''"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

# =========================================================================
# PCT-T21: historical backtest — last N merged cycle PRs should all classify as cycle
# =========================================================================
# From `git log --oneline main --grep='cycle-'`, representative PR titles:

@test "backtest: representative cycle PR titles all classify as cycle" {
    # Representative titles drawn from recent merged cycle PRs.
    # Each carries a cycle-NNN, cycle prefix, or Run Mode / Sprint Plan marker.
    titles=(
      "feat(models): promote Opus 4.7 to top-review default (cycle-082)"
      "fix(skills): drop restrictive agent: on write-capable skills + lint invariant (cycle-083)"
      "fix(update-loa): refresh version markers post-merge (Phase 5.6) (cycle-083)"
      "feat(bridge): multi-model Bridgebuilder pipeline (cycle-052)"
      "feat(bridge): Amendment 1 post-PR loop + kaironic convergence (cycle-053)"
      "feat(harness): spiral autopoietic orchestrator (cycle-071)"
      "Run Mode: autonomous sprint implementation 1"
      "Sprint Plan: cycle-060 platform hardening"
      "feat(sprint-3): token budget enforcement"
      "feat(cycle-042): mining runtime routing"
      "feat(vision-registry): query API and lifecycle (cycle-069)"
      "feat(simstim): HITL accelerated development workflow (cycle-048)"
      "fix(harness): CLAUDE.md blocks, permission flags (cycle-071)"
      "feat(flatline): 3-model tertiary support (cycle-040)"
    )
    for title in "${titles[@]}"; do
        run "$CLASSIFIER" --title "$title"
        if [[ "$output" != "cycle" ]]; then
            echo "FAILED to classify as cycle: $title" >&2
            echo "Got: $output" >&2
            return 1
        fi
    done
}

@test "non-cycle feat PRs without cycle-NNN classify as other" {
    # PRs that are legitimate feat work but not part of a cycle ship.
    # They should get the simple tag-only release path, not Full Pipeline.
    titles=(
      "feat(adversarial-review): enforce Phase 2.5 at COMPLETED marker write"
      "feat(auth): implement OAuth2 flow"
      "feat(api): add user endpoint"
    )
    for title in "${titles[@]}"; do
        run "$CLASSIFIER" --title "$title"
        if [[ "$output" != "other" ]]; then
            echo "Expected 'other', got '$output' for: $title" >&2
            return 1
        fi
    done
}

# =========================================================================
# PCT-T28..PCT-T40: housekeeping merges (bd-ahxmh, bd-nr5i6)
# =========================================================================
# The archive branch carries the cycle id by convention (chore/cycle-NNN-archive),
# so the cycle-NNN rule routed every archive merge to the cycle release path:
# Post-Merge Pipeline runs 40112908074 (PR #1293) and 40182103691 (PR #1297)
# each ran the cycle release pipeline. A chore/ branch merge or a
# chore(archive|ledger|decisions): prefix is housekeeping; labels keep
# precedence; a bare chore: or chore(release): naming a cycle stays cycle.
# bd-ahxmh (sprint-bug-277) routed housekeeping to `other`, which still ran the
# Bugfix-or-Other prepare job; bd-nr5i6 (cycle-135 C-4) gives it its own value,
# `housekeeping`, for which post-merge.yml runs neither prepare job
# (post-merge-workflow-guards.bats). T35 (bare chore:) stays `other`.

@test "PCT-T28: cycle-133 archive merge subject (PR #1293) → housekeeping (bd-ahxmh, bd-nr5i6)" {
    run "$CLASSIFIER" --title "Merge pull request #1293 from 0xHoneyJar/chore/cycle-133-archive — cycle-133 archive"
    [ "$status" -eq 0 ]
    [ "$output" = "housekeeping" ]
}

@test "PCT-T29: cycle-134 archive merge subject (PR #1297) → housekeeping (bd-ahxmh, bd-nr5i6)" {
    run "$CLASSIFIER" --title "Merge pull request #1297 from 0xHoneyJar/chore/cycle-134-archive — cycle-134 archive"
    [ "$status" -eq 0 ]
    [ "$output" = "housekeeping" ]
}

@test "PCT-T30: squash-form chore(archive): subject naming a cycle → housekeeping (bd-ahxmh, bd-nr5i6)" {
    run "$CLASSIFIER" --title "chore(archive): cycle-134 post-ship fixes — archive directory, ledger archived (#1297)"
    [ "$status" -eq 0 ]
    [ "$output" = "housekeeping" ]
}

@test "PCT-T31: publisher's chore(ledger): push subject naming a cycle → housekeeping (bd-ahxmh, bd-nr5i6)" {
    run "$CLASSIFIER" --title "chore(ledger): archive cycle-134-post-ship-fixes after merge"
    [ "$status" -eq 0 ]
    [ "$output" = "housekeeping" ]
}

@test "PCT-T32: decisions-confirm merge from a chore/ branch (PR #1298) → housekeeping (bd-ahxmh, bd-nr5i6)" {
    run "$CLASSIFIER" --title "Merge pull request #1298 from 0xHoneyJar/chore/cycle-134-decisions-confirm — confirmed rows"
    [ "$status" -eq 0 ]
    [ "$output" = "housekeeping" ]
}

@test "PCT-T33: chore/ branch merge with a cycle label → cycle (labels keep precedence)" {
    run "$CLASSIFIER" --title "Merge pull request #9 from o/chore/cycle-1-archive — x" --labels "cycle,release"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

@test "PCT-T34: feature/ branch sprint merge naming a cycle (PR #1296) → cycle (unchanged)" {
    run "$CLASSIFIER" --title "Merge pull request #1296 from 0xHoneyJar/feature/cycle-134-post-ship-fixes — cycle-134 post-ship fixes (Sprint 276)"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

@test "PCT-T35: chore: without a cycle id → other (prefix rule's lower bound)" {
    run "$CLASSIFIER" --title "chore: bump deps"
    [ "$status" -eq 0 ]
    [ "$output" = "other" ]
}

@test "PCT-T36: chore(release): named-release squash naming a cycle (PR #747) → cycle (unchanged)" {
    run "$CLASSIFIER" --title "chore(release): v1.130.0 — named milestone (cycle-098 + cycle-099 + cheval headless adapters) (#747)"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

@test "PCT-T37: release/ branch with a chore segment deeper in the path → cycle (clause anchored to the first segment)" {
    run "$CLASSIFIER" --title "Merge pull request #1300 from 0xHoneyJar/release/chore/v2.1.0 — release"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

@test "PCT-T38: chore/ first segment with a release segment deeper → housekeeping (chore/ is housekeeping by convention; bd-nr5i6)" {
    run "$CLASSIFIER" --title "Merge pull request #1301 from 0xHoneyJar/chore/release/v2.1.0 — x"
    [ "$status" -eq 0 ]
    [ "$output" = "housekeeping" ]
}

# PCT-T39..PCT-T40 are pins (both pass before and after bd-ahxmh): label
# precedence over the prefix form, and the deliberate case-sensitivity.

@test "PCT-T39: chore(archive): prefix with a cycle label → cycle (a label beats the prefix form too)" {
    run "$CLASSIFIER" --title "chore(archive): cycle-1 x" --labels "cycle"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}

@test "PCT-T40: Chore(archive): capitalised → cycle (case-sensitive by design; falls through to the cycle-id rule)" {
    run "$CLASSIFIER" --title "Chore(archive): cycle-1 x"
    [ "$status" -eq 0 ]
    [ "$output" = "cycle" ]
}
