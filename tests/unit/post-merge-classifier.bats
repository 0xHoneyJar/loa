#!/usr/bin/env bats
# =============================================================================
# post-merge-classifier.bats — Tests for classify-pr-type.sh (Issue #550)
# =============================================================================
# Sprint-bug-104. Validates the shared PR-type classifier that routes merged
# PRs into the Simple Release or Full Pipeline job in post-merge automation.

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
