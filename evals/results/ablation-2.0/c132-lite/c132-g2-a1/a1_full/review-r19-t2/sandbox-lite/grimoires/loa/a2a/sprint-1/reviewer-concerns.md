# Reviewer concerns — sprint-1 (PR: sprint-255, cycle-129)

Scope: pr/head.diff (81 files). Phase 2 notes for the cross-model dissent.

1. `grimoires/loa/guards.md` (the tracked structural register that `guard-yield.sh --check` compares against) is not part of the change, and `.gitignore` does not ignore it. The new CI step `bash .claude/scripts/guard-yield.sh --check` in `.github/workflows/bats-tests.yml` and test GO-9 in `tests/unit/guard-origins.bats` therefore fail on this PR as submitted (drift: file missing).
2. `evals/harness/execute-agent.sh` `rule_files` toggle: when neither rule file exists in the sandbox the toggle records `removed: none present` and continues, contradicting the header contract "a toggle that cannot take effect is exit 2 (an arm never silently runs as its baseline)".
3. `guard-yield.sh` sources `.claude/scripts/lib/heredoc-classifier.sh` at run time (`source "$HEREDOC_LIB"`); a library with side effects on source (stdin read, exit) would silently truncate the run. Verify.
4. `.github/workflows/check-prompt-budget.yml` header comment now states 160,000 / 114,688 B while `tools/check-prompt-budget.sh` is not in the diff; test PB-10 pins the comment to the tool's constants.
5. `.claude/skills/implementing-tasks/SKILL.md` app zone permission changed read → read-write with no mention in the PR description (drive-by).
6. `validate-artifact.sh validate_sprint_kinds` and `tools/cycle-ratio.sh` parse the same `kind:` token with different rules (code spans stripped vs not).
7. `run-arms.sh is_transport_failure` greps `5[0-9][0-9] ` in agent stderr/stdout: any three-digit number starting with 5 followed by a space counts as a transport failure.
8. `guard-yield.sh` burst heuristic: ten block rows in one UTC minute are classed as replay even from a live session.
