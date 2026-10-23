# Reviewer concerns (Phase 2 notes, preliminary)

Scope: sprint-252 decision surfaces part 1. New shell: dec-write-lib.sh (ledger writer),
loa-decisions-surface.sh (SessionStart hook), tools/check-round-independence.sh, /decisions
command, user-invoked-commands.txt allowlist, validate-artifact.sh --type decisions,
grimoire-index.sh changes, .gitignore negation, skill prose (rounds pacing).

Areas to probe:
- Does the tracked ledger grimoires/loa/decisions.yaml actually exist / get created? The PR
  negates the gitignore but adds no ledger file; live writes die "ledger not found".
- Operator-only enforcement: --recorded-by decisions-command is a plain CLI flag any agent can pass.
- import: gsub of PEND ids over all strings; --rewrite awk gsub treats keys as regex; rm -f pending.
- confirm: supersede handling reads $cur before replace; superseded row transitions.
- Lock: flock fd 9 on path; mkdir fallback stale check; lock under PROJECT_ROOT/.run even for --file fixtures.
- is_unattended called repeatedly; PRD status grep.
- surface hook: jq regex with \u0080-\u009f in character class; LOA_HOOK_CONTEXT; schema check.
- check-round-independence: grep -oE on multi-block lines; depends_on on reasked id in same round.
- validate-artifact.sh --type decisions --base-file semantics (append-only enforcement).
- Tests: do bats assertions actually verify behaviour; harness test for disable-model-invocation.
