# Reviewer concerns (Phase 2 notes) — sprint-1, PR "sprint-252 decision surfaces, part 1"

1. dec-write-lib.sh: `is_unattended()` folds the PRD Status line ("autonomous|unattended") into the unattended verdict. That signal is a permanent artifact property, not a live signal, yet it drives derive_attribution for confirm/reject/supersede: an operator confirm with --answer-ref cli:... records decided_by agent; an operator reject of a decided row dies; an operator supersede lands as an agent proposal.
2. dec-write-lib.sh resolve_target: any --file target is TARGET_KIND=fixture, so `--file grimoires/loa/decisions.yaml` bypasses the CI/GITHUB_ACTIONS/LOA_HOOK_CONTEXT refusal and the worktree→pending redirect; confirm/supersede on a --file pending file also escape their pending-file refusals.
3. dec-write-lib.sh op_import --rewrite: paths are not validated (no project containment, symlinks replaced by regular files, '..' allowed), and the awk gsub treats PEND ids as regexes.
4. validate-artifact.sh: --base-file-less path compares against merge-base; "more than one transition appended in one write" fires on a branch with several writes to one row, so a CI run against merge-base fails legitimate histories.
5. loa-decisions-surface.sh: literal U+2028/U+2029 bytes inside the jq character class (invisible in source); when the surface is enabled but yq v4/jq are missing the hook exits silently instead of a WARNING line (contract asymmetry vs loa-kf-surface).
6. grimoire-index.sh emit_decisions: summary is not angle-bracket-neutralised unlike the session-start surface; INDEX.md is agent-read.
7. user-invoked-harness.bats runs a live, paid `claude -p` call by default in the unit suite whenever the CLI is on PATH.
8. .loa.config.yaml.example sets `pacing: rounds` explicitly, which defeats the documented "minimal → batch" default.
9. discovering-requirements SKILL.md cfg() quoting: `yq eval "$1 // \"$2\""` returns the literal string for booleans; fine, but `.interview.pacing // ""` yields empty string correctly only with yq v4.
10. grimoire-index.bats references loa-learnings-index.sh decisions indexing and path-lib.sh get_decisions_path, which this PR does not add.
