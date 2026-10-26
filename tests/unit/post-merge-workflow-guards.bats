#!/usr/bin/env bats
# =============================================================================
# post-merge-workflow-guards.bats — the post-merge job guards (KF-063,
# bd-hyx0n, cycle-134 Task 1.6; sdd.md C-8, D-3.1; housekeeping allowlist,
# bd-nr5i6, cycle-135 Task 1.6, sdd.md C-4, D-1.4a)
# =============================================================================
# Run 40112013975 (on 928b3b9e): the publisher's ledger fast-forward
# (`chore(ledger): archive <cycle> after merge`, no PR) was classified
# pr_type=cycle with an empty pr_number and the full-pipeline job aborted on
# `--pr is required`. Two independent layers now hold: the classifier says
# `other` when there is no PR number (classify-merge-pr.bats KF063-*), and
# both preparation jobs require a PR number. PMWG-T1 … T4 read the workflow
# text with yq. PMWG-T5 evaluates the guards through a shell mirror of the
# exact expressions (_guard_runs below), so the routing table is checked, not
# only the text (sprint Flatline gpt IMP-017, opus IMP-009); GitHub's own
# expression evaluator is not executed.
#
# bd-nr5i6: housekeeping merges (archive, the orchestrator's ledger push,
# decisions confirmations) classify `housekeeping` and prepare nothing. The
# simple-release guard is an allowlist (bugfix, other), so `housekeeping`, an
# unknown value and an empty value run neither job.
#
#   case                    | pr_type      | pr_number | simple-release | full-pipeline
#   ------------------------+--------------+-----------+----------------+--------------
#   ordinary push (no PR)   | other        | (empty)   | no             | no
#   cycle merge             | cycle        | 1295      | no             | yes
#   non-cycle merge         | bugfix/other | 1296      | yes            | no
#   housekeeping merge      | housekeeping | 1297      | no             | no
#   unknown value           | (anything)   | 1298      | no             | no
#   classification failure  | (empty)      | (empty)   | no             | no
#
# A push without a PR runs neither job, as intended (opus IMP-025).
# =============================================================================

setup() {
    WORKFLOW="$BATS_TEST_DIRNAME/../../.github/workflows/post-merge.yml"
    command -v yq >/dev/null 2>&1 || skip "yq not installed"
}

job_if() { yq -r ".jobs[\"$1\"].if" "$WORKFLOW"; }

# The guard texts this file pins (post-merge.yml `if:` lines, verbatim).
SR_GUARD="(needs.classify.outputs.pr_type == 'bugfix' || needs.classify.outputs.pr_type == 'other') && needs.classify.outputs.pr_number != ''"
FP_GUARD="needs.classify.outputs.pr_type == 'cycle' && needs.classify.outputs.pr_number != ''"
# The negative-list form simple-release carried before bd-nr5i6; mirrored so
# PMWG-T5 shows on the old text why housekeeping prepared (it is red there).
SR_GUARD_LEGACY="needs.classify.outputs.pr_type != 'cycle' && needs.classify.outputs.pr_number != ''"

# _guard_runs <if-expression> <pr_type> <pr_number> — the shell mirror.
# Returns 0 when a job with that `if:` would run, 1 when it would be skipped,
# 2 when the expression is not one this mirror knows (the caller fails, so a
# guard edit cannot slip past the matrix). Each branch transcribes its
# expression operator by operator. GitHub compares strings case-insensitively
# (`==`/`!=` in expressions), hence `${t,,}`; a missing output reads as '',
# hence the plain empty-string tests.
_guard_runs() {
    local expr="$1" t="${2,,}" n="$3"
    case "$expr" in
        "$SR_GUARD")        [[ ( "$t" == 'bugfix' || "$t" == 'other' ) && "$n" != '' ]] ;;
        "$FP_GUARD")        [[ "$t" == 'cycle' && "$n" != '' ]] ;;
        "$SR_GUARD_LEGACY") [[ "$t" != 'cycle' && "$n" != '' ]] ;;
        *) echo "no shell mirror for guard text: $expr" >&2; return 2 ;;
    esac
}

@test "PMWG-T1: simple-release requires a PR number and an allowlisted type (bugfix or other; bd-nr5i6)" {
    guard="$(job_if simple-release)"
    [ "$guard" = "$SR_GUARD" ]
    [[ "$guard" == *"needs.classify.outputs.pr_number != ''"* ]]
    [[ "$guard" != *"!= 'cycle'"* ]]
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

@test "PMWG-T5: shell mirror of both guards over {cycle, bugfix, other, housekeeping, unknown, empty} x {PR, none} (bd-nr5i6)" {
    local sr fp t n want_sr want_fp got_sr got_fp rc row
    sr="$(job_if simple-release)"
    fp="$(job_if full-pipeline)"
    # pr_type | pr_number | simple-release | full-pipeline (1 = runs)
    local -a matrix=(
        "cycle|123|0|1"        "cycle||0|0"
        "bugfix|123|1|0"       "bugfix||0|0"
        "other|123|1|0"        "other||0|0"
        "housekeeping|123|0|0" "housekeeping||0|0"
        "unknown|123|0|0"      "unknown||0|0"
        "|123|0|0"             "||0|0"
    )
    for row in "${matrix[@]}"; do
        IFS='|' read -r t n want_sr want_fp <<<"$row"
        rc=0; _guard_runs "$sr" "$t" "$n" || rc=$?
        [ "$rc" -ne 2 ] || return 1
        got_sr=$(( rc == 0 ? 1 : 0 ))
        rc=0; _guard_runs "$fp" "$t" "$n" || rc=$?
        [ "$rc" -ne 2 ] || return 1
        got_fp=$(( rc == 0 ? 1 : 0 ))
        if [[ "$got_sr" != "$want_sr" || "$got_fp" != "$want_fp" ]]; then
            echo "pr_type='$t' pr_number='$n': simple-release=$got_sr (want $want_sr) full-pipeline=$got_fp (want $want_fp)" >&2
            return 1
        fi
    done
}

@test "PMWG-T6: yq e reads the simple-release guard as the allowlist expression (bd-nr5i6)" {
    run yq e '.jobs."simple-release".if' "$WORKFLOW"
    [ "$status" -eq 0 ]
    [ "$output" = "$SR_GUARD" ]
    run yq e '.jobs."full-pipeline".if' "$WORKFLOW"
    [ "$status" -eq 0 ]
    [ "$output" = "$FP_GUARD" ]
}

@test "PMWG-T7: the simple-release guard names bd-nr5i6 and the unknown-value rule in a comment" {
    grep -B8 "if: (needs.classify.outputs.pr_type == 'bugfix'" "$WORKFLOW" | grep -q 'bd-nr5i6'
    grep -B8 "if: (needs.classify.outputs.pr_type == 'bugfix'" "$WORKFLOW" | grep -qi 'unknown'
}

@test "PMWG-T8: actionlint accepts the workflow (skipped when actionlint is not installed)" {
    command -v actionlint >/dev/null 2>&1 || skip "actionlint not installed"
    run actionlint "$WORKFLOW"
    [ "$status" -eq 0 ]
}
