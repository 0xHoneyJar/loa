# Reviewer concerns (Phase 2 notes) — sprint-1, PR: sprint-252 decision surfaces part 1

- tests/unit/dec-write-lib.bats, grimoire-index.bats, validate-artifact.bats read a tracked grimoires/loa/decisions.yaml from the repo root; the change adds no such file (not in head.diff). Suites fail in setup().
- dec-write-lib.sh op_reject: rejecting an agent-proposed superseding row leaves the old decided row's supersede_proposed_by set, so later agent supersede attempts die "already proposed" forever.
- dec-write-lib.sh op_supersede (operator path): old row goes to superseded immediately while the replacement is only proposed; rejecting the replacement leaves no live decision.
- dec-write-lib.sh op_confirm: with no --answer-ref, decided_by becomes the proposing voice (agent) even though the operator confirmed; by is operator:decisions-command.
- loa-decisions-surface.sh: WARNING printed every session when ledger absent and key on.
- validate-artifact.sh validate_decisions: shells out to dec-write-lib.sh context --why; PRD check depends on sibling ledger.
- check-round-independence.sh: one block per line assumption; greedy regex merges two blocks on one line.
- grimoire-index.sh: voice field added to all families' JSON; INDEX.md header text not updated.
