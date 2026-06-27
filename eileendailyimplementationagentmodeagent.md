# Eileen Daily Implementation Agent Mode Agent

This is the repo-local runbook for the daily GPT-5.5 Thinking implementation agent. The daily agent prompt must explicitly read this file before editing this repo. The purpose is not only to code: the agent must first explain what should be implemented, why it matters, why it fits this repo, how it advances the repo endgame, and how the implementation remains safe at scale.

## Repository responsibility

`0xHoneyJar/loa` owns the Loa agent-driven development framework: workflow commands, agent orchestration, quality gates, review/ship loops, task memory, and developer-operating-system behavior.

This repo is not the place for product-specific Freeside behavior, Straylight estate semantics, Dixie API runtime enforcement, Hounfour schema packages, Finn experiment conclusions, Aleph research-précis doctrine, or Arcturus revenue-oracle logic.

## Eligible input

Only implement from a Daily Deep Research Report issue or follow-up plan-audit item with:

- `PROPOSED_NEXT_LANE_SEED`
- candidate ID
- repo-fit reasoning
- acceptance criteria
- rollback path
- `VERDICT: ACCEPT_PLAN`

Without `VERDICT: ACCEPT_PLAN`, the agent may self-audit only docs, fixtures, tests, or checkers. Runtime-sensitive work requires explicit external acceptance.

## Mandatory pre-implementation thesis

Before editing, write this in the run log and later carry it into the PR body:

1. Candidate chosen: issue, candidate ID, and verdict.
2. What should be implemented: precise change, not a vague theme.
3. Why this should be implemented now: source evidence plus current repo state.
4. Why this belongs in `loa`: repo-fit and why sibling repos should not own it.
5. What this is good for: developer/agent workflow improvement and future leverage.
6. Why this approach should work: mechanism, expected behavior, and proof path.
7. Endgame contribution: how this moves Loa toward a better agentic development framework.
8. Creative/innovative extension path: next possible lanes after this PR, clearly marked as future work.
9. Mass-user scaling impact: whether the change improves, preserves, or risks scale characteristics.
10. Security scope: trust boundaries, data/code execution surfaces, and misuse risks.
11. Simplification / exploit-prevention argument: how the change reduces complexity or avoids new exploit paths.
12. Non-goals and forbidden surfaces.
13. Tests/checks and rollback path.

If the agent cannot complete this thesis convincingly, it must not implement.

## Additive-only policy

Nothing currently working may stop functioning.

Allowed by default: new docs, examples, fixtures, tests, validators/checkers, default-off helpers, review/audit checklist improvements.

Forbidden without explicit Eileen approval: deleting files, renaming public commands or exports, changing default command behavior, changing bootstrap behavior, broad refactors, unrelated dependency upgrades, secrets or real env changes, sibling repo mutation, deployment changes, auto-merge, or closing source issues.

## Loa-specific stop conditions

Stop and return `VERDICT: NEEDS_HUMAN` if the candidate would change a Golden Path command contract, alter `/loa`, `/plan`, `/build`, `/review`, or `/ship` semantics, change framework memory/state behavior by default, rewrite Claude/Codex role boundaries, or introduce hidden repo-mutating automation.

## Implementation steps

1. Read this file, README/package scripts, and relevant docs near the target surface.
2. Confirm the source item has `VERDICT: ACCEPT_PLAN`.
3. Check for obvious duplicate open issues/PRs.
4. Write the mandatory pre-implementation thesis.
5. Create a branch named `daily-impl/YYYY-MM-DD-loa-<candidate>`.
6. Implement exactly one candidate with a minimal diff.
7. Prefer simpler code and explicit checks over clever abstractions.
8. Run relevant checks.
9. Open a draft PR.
10. Add `CODEX AUDIT REQUEST` and the required traceability report.
11. Comment: `@codex review for additive-only scope violations, accidental default-behavior changes, scaling risks, security regressions, exploit-prone complexity, failing or missing tests, rollback clarity, and repo-boundary violations`.
12. Do not merge and do not close the source issue.

## Required PR traceability report

Every implementation PR must include:

- Source issue and candidate ID
- Pre-implementation thesis summary
- What changed, with file-by-file commit/change rationale
- Why each changed file is good for this repo
- Why the implementation advances the repo endgame
- Why this implementation should work
- Mass-user scaling analysis
- Security scope and exploit/hack prevention analysis
- Simplicity analysis: what complexity was avoided
- Tests/checks run and results
- Skipped checks with reason
- Rollback path
- Future creative/innovative solution paths not implemented in this PR
- `CODEX AUDIT REQUEST`

## Final run report

Report selected repo, source issue, branch, PR URL, files changed, checks run, Codex review status, blockers, and boundaries approached.
