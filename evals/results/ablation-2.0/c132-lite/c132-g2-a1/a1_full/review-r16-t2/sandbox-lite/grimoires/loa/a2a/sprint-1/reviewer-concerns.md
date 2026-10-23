# Reviewer concerns (Phase 2 notes) — sprint-1 / PR "sprint-252 decision surfaces, part 1"

Scope: pr/head.diff (39 files). Core logic: .claude/scripts/lib/dec-write-lib.sh (new, 741 lines),
.claude/scripts/validate-artifact.sh (--type decisions + prd/sdd/sprint hooks),
.claude/hooks/session-start/loa-decisions-surface.sh, .claude/scripts/grimoire-index.sh (decisions family),
tools/check-round-independence.sh, .claude/data/user-invoked-commands.txt + disable-model-invocation flags.

Concerns found so far:

1. The ledger file grimoires/loa/decisions.yaml is never added or bootstrapped by the PR, yet `dec-write-lib.sh new`
   dies "ledger not found" without it (dec-write-lib.sh:271) and three bats suites read it in setup
   (dec-write-lib.bats:28, grimoire-index.bats, validate-artifact.bats) — setup errors when absent.
   .gitignore:149-150 ignores then negates it; base had it ignored so it cannot have been tracked.
2. is_unattended() (dec-write-lib.sh:183) folds the PRD **Status** line into the unattended signal. confirm only
   refuses on live signals (509) but derive_attribution (313) ignores --answer-ref under any signal, so a PRD
   saying "autonomous" makes every operator confirm land decided_by: agent (538). reject/supersede operator paths
   (572-576, 600-611) also degrade to the agent path under the PRD signal.
3. --file <path> is always TARGET_KIND=fixture (251): naming the live ledger with --file bypasses the CI/hook
   refusal (261) and the worktree→pending redirect (255).
4. import --rewrite PATH (649-653) rewrites and mv -f's over any path, no project-root containment, follows symlinks.
5. reject of a proposed replacement row leaves the old decided row's supersede_proposed_by pointing at the rejected
   row; the agent supersede path then refuses forever (601).
6. grimoire-index.sh emit_decisions sanitiser (s) strips C0 + U+2028/9 only: no C1 strip, < and > pass through into
   INDEX.md / .run/grimoire-index.json (untrusted agent text; loa-decisions-surface.sh does replace them).
7. loa-decisions-surface.sh:69 embeds raw U+2028/U+2029 bytes inside the jq regex (invisible in source).
8. validate_prd_assumptions: `awk ... index($2, n)` matches the PRD basename anywhere in source — "prd.md" matches
   "myprd.md#x"; DEC-id regex `DEC-[0-9]{4,}` on prose lines also matches ids in unrelated text.
9. check-round-independence.sh: BLOCK_RE `\[.*\]` greedy — two blocks on one line merge; `--` handling leaves
   trailing args parsed as flags.
10. user-invoked-commands.txt adds run-halt / loa-setup / contribute as operator-only; need to verify no skill body
    invokes them as an orchestrator step (run-mode halting?).
11. validate-artifact.sh decisions: merge-base fallback uses origin/main; _dec_context_why runs the lib's context
    from the validator's own tree rather than PROJECT_ROOT (test fixtures copy both, so masked).
