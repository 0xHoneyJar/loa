# Reviewer concerns — sprint-1 (PR: sprint-252 decision surfaces, part 1)

Scope: pr/head.diff (39 files). Primary code: .claude/scripts/lib/dec-write-lib.sh (new),
.claude/hooks/session-start/loa-decisions-surface.sh (new), tools/check-round-independence.sh (new),
validate-artifact.sh --type decisions (+ prd/sdd/sprint checks), grimoire-index.sh decisions family,
operator-only command flags (disable-model-invocation), .gitignore negation.

Concerns to challenge or confirm:

1. dec-write-lib.sh derive_attribution / op_confirm / op_reject / op_supersede use is_unattended(),
   which includes the PRD `**Status:**` line signal (kind "prd"). The operator's /decisions confirm
   is allowed under a prd-only signal (live_run_signal gate) but then --answer-ref is ignored and
   decided_by falls back to proposed_by ("agent"). Operator reject of a decided row dies; operator
   supersede degrades to the agent path. Attribution defect in the core feature.
2. resolve_target: any --file target is TARGET_KIND=fixture, so `--file grimoires/loa/decisions.yaml`
   bypasses the CI/GITHUB_ACTIONS/LOA_HOOK_CONTEXT refusal and the linked-worktree pending redirect
   (DEC id collisions across worktrees).
3. op_import --rewrite: arbitrary path rewritten in place (no project-root containment, symlink
   replaced by regular file).
4. Hook exits silently when yq v4/jq missing even if the surface is enabled (looks disabled).
5. Hook jq clean regex relies on literal invisible U+2028/U+2029 characters in source.
6. grimoire-index emit_decisions does not neutralise `<`/`>` in untrusted summaries written to INDEX.md.
7. help text `sed -n '2,45p'` prints the `export LC_ALL=C` line.
8. check-round-independence: a depends_on naming a *reasked* question in the same round is flagged
   as same-round dependency although it was asked earlier.
9. validate-gitignore-state is_ignored_match: source paths containing ':' mis-parse.
10. Tests: dec-write-lib.bats confirm-under-PRD test asserts status only, not decided_by.
11. The live ledger grimoires/loa/decisions.yaml is not in the diff although tests and the
    .gitignore negation assume it is tracked with a specific header comment.
