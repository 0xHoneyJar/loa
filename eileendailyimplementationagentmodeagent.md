# Eileen Daily Implementation Agent Mode Agent

This file is the repo-local runbook for the daily GPT-5.5 Thinking implementation agent. The daily agent prompt must explicitly read this file before editing this repo. This file is intentionally separate from `AGENTS.md`; it is a workflow contract for converting Daily Deep Research Report issues into additive implementation PRs.

## Repository responsibility

`0xHoneyJar/loa` owns the Loa agent-driven development framework: workflow commands, agent orchestration, quality gates, review/ship loops, task memory, and developer-operating-system behavior.

This repo is not the place for product-specific Freeside behavior, Straylight estate semantics, Dixie API runtime enforcement, Hounfour schema packages, Finn experiment conclusions, Aleph research-précis doctrine, or Arcturus revenue-oracle logic.

## Eligible input

Only implement from a Daily Deep Research Report issue or follow-up plan-audit issue/comment that contains:

- `PROPOSED_NEXT_LANE_SEED`
- candidate ID
- repo-fit reasoning
- acceptance criteria
- rollback path
- `VERDICT: ACCEPT_PLAN`

If the candidate lacks `VERDICT: ACCEPT_PLAN`, the agent may perform in-run plan audit only for docs, fixtures, tests, or checkers. Runtime-sensitive work requires explicit external acceptance.

## Selection rule

Pick at most one candidate per run. Prefer the lowest-risk candidate that improves future agent/developer workflow reliability.

Priority order:

1. docs-only workflow guidance
2. fixture-only examples
3. test-only coverage
4. checker/validator-only additions
5. default-off framework helpers

## Additive-only policy

Nothing currently working may stop functioning.

Allowed by default:

- new docs
- new examples/fixtures
- new tests
- new validation/checker scripts
- new default-off commands or helpers
- review/audit checklist improvements

Forbidden without explicit Eileen approval:

- deleting files
- renaming public commands or exports
- changing default command behavior
- changing project bootstrap behavior
- broad refactors
- unrelated dependency upgrades
- secrets or real env changes
- sibling repo mutation
- deployment changes
- auto-merge
- closing source issues

## Loa-specific stop conditions

Stop and return `VERDICT: NEEDS_HUMAN` if the candidate would:

- change a Golden Path command contract
- alter `/loa`, `/plan`, `/build`, `/review`, or `/ship` semantics
- change framework memory/state behavior by default
- rewrite Claude/Codex role boundaries
- introduce hidden automation that can mutate repos without explicit issue/PR authority

## Implementation steps

1. Read this file, README/package scripts, and relevant docs near the target surface.
2. Inspect the source issue and confirm `VERDICT: ACCEPT_PLAN`.
3. Check for obvious duplicate open issues/PRs.
4. Write a short plan: selected candidate, implementation class, allowed files, forbidden surfaces, checks, rollback.
5. Create a branch named `daily-impl/YYYY-MM-DD-loa-<candidate>`.
6. Implement exactly one candidate with a minimal diff.
7. Run relevant checks from the repo.
8. Open a draft PR.
9. Add `CODEX AUDIT REQUEST` to the PR body.
10. Comment: `@codex review for additive-only scope violations, accidental default-behavior changes, failing or missing tests, rollback clarity, repo-boundary violations, and security regressions`.
11. Do not merge and do not close the source issue.

## PR body requirements

The PR must include:

- source issue
- candidate ID
- implementation class
- what changed
- what did not change
- checks run
- skipped or failing checks
- rollback path
- Codex audit request

## Final run report

Report the selected repo, source issue, branch, PR URL, files changed, checks run, Codex review status, blockers, and whether any boundary was approached.
