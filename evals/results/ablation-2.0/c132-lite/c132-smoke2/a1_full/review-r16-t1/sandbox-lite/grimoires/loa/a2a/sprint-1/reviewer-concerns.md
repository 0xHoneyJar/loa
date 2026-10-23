# Reviewer concerns (Phase 2 notes) — sprint-1, PR "sprint-252 decision surfaces, part 1"

1. grimoires/loa/decisions.yaml is never added by the diff, yet dec-write-lib.sh dies "ledger not found" on the live path and three bats suites read $REPO/grimoires/loa/decisions.yaml in setup.
2. dec-write-lib.sh op_confirm: derive_attribution drops --answer-ref whenever is_unattended (which includes a PRD "**Status:** ... autonomous" line), but confirm only blocks on live signals. Result reproduced: operator confirm lands decided_by: agent, decided_by_ref: null, and validator accepts it.
3. resolve_target: --file bypasses ci_blocked entirely, so `--file grimoires/loa/decisions.yaml` writes the live ledger under CI=1 (reproduced).
4. is_operator_call is a CLI string (--recorded-by decisions-command); any Bash-capable agent can confirm its own rows outside a live run. Guard is lint-only (tests grep skills/commands).
5. loa-decisions-surface.sh exits silently when yq v4 is missing even if enabled (contract says so, but the KF surface pattern prints a WARNING).
6. validate-artifact.sh validate_prd_assumptions matches the PRD by basename substring (index($2, "prd.md")) so "sprint-prd.md" or any source containing prd.md satisfies the rule.
7. op_import --rewrite uses awk gsub with PEND ids as regex; safe charset, but map is applied to arbitrary files named by the caller.
8. grimoire-index.sh / dec-write-lib list: free-text to markdown; pipes escaped, control chars stripped — looks fine.
9. check-round-independence.sh: per-round "new" for malformed rounds is 0, lowering the average; acceptable.
