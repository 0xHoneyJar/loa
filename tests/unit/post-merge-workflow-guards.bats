#!/usr/bin/env bats
# =============================================================================
# post-merge-workflow-guards.bats — the post-merge job guards (KF-063,
# bd-hyx0n, cycle-134 Task 1.6; sdd.md C-8, D-3.1)
# =============================================================================
# Run 40112013975 (on 928b3b9e): the publisher's ledger fast-forward
# (`chore(ledger): archive <cycle> after merge`, no PR) was classified
# pr_type=cycle with an empty pr_number and the full-pipeline job aborted on
# `--pr is required`. Two independent layers now hold: the classifier says
# `other` when there is no PR number (classify-merge-pr.bats KF063-*), and
# both preparation jobs require a PR number. These assertions read the
# workflow text with yq; there is no expression evaluator (gpt IMP-019,
# IMP-009 accepted in part).
#
# Representative classifier outputs and the intended routing:
#
#   case                    | pr_type      | pr_number | simple-release | full-pipeline
#   ------------------------+--------------+-----------+----------------+--------------
#   ordinary push (no PR)   | other        | (empty)   | no             | no
#   cycle merge             | cycle        | 1295      | no             | yes
#   non-cycle merge         | bugfix/other | 1296      | yes            | no
#   classification failure  | (empty)      | (empty)   | no             | no
#
# A push without a PR runs neither job, as intended (opus IMP-025).
# =============================================================================

setup() {
    WORKFLOW="$BATS_TEST_DIRNAME/../../.github/workflows/post-merge.yml"
    command -v yq >/dev/null 2>&1 || skip "yq not installed"
}

job_if() { yq -r ".jobs[\"$1\"].if" "$WORKFLOW"; }

@test "PMWG-T1: simple-release requires a PR number and a non-cycle type" {
    guard="$(job_if simple-release)"
    [ "$guard" = "needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_number != ''" ]
    [[ "$guard" == *"needs.classify.outputs.pr_number != ''"* ]]
}

@test "PMWG-T2: full-pipeline requires a PR number and the cycle type (KF-063)" {
    guard="$(job_if full-pipeline)"
    [ "$guard" = "needs.classify.outputs.pr_type == 'cycle' && needs.classify.outputs.pr_number != ''" ]
    [[ "$guard" == *"needs.classify.outputs.pr_number != ''"* ]]
    [[ "$guard" == *"needs.classify.outputs.pr_type == 'cycle'"* ]]
}

@test "PMWG-T3: both preparation jobs depend on classify, and no other job reads its outputs unguarded" {
    [ "$(yq -r '.jobs["simple-release"].needs' "$WORKFLOW")" = classify ]
    [ "$(yq -r '.jobs["full-pipeline"].needs' "$WORKFLOW")" = classify ]
    # Every job that needs classify carries the pr_number guard.
    while IFS= read -r job; do
        [[ "$(job_if "$job")" == *"needs.classify.outputs.pr_number != ''"* ]] || {
            echo "job $job needs classify without a pr_number guard" >&2
            return 1
        }
    done < <(yq -r '.jobs | to_entries[] | select(.value.needs == "classify" or ((.value.needs | type) == "!!seq" and (.value.needs[] == "classify"))) | .key' "$WORKFLOW")
}

@test "PMWG-T4: the full-pipeline guard names KF-063 and the run in a comment" {
    grep -B6 "if: needs.classify.outputs.pr_type == 'cycle'" "$WORKFLOW" | grep -q 'KF-063'
    grep -B6 "if: needs.classify.outputs.pr_type == 'cycle'" "$WORKFLOW" | grep -q '40112013975'
}
