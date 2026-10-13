# E2E transcript: cycle-128 Sprint 3 scoping interview in `rounds` pacing

A second transcript for `tools/check-round-independence.sh` (Task 3.E2E, goal G-3), distinct
from the Sprint 1 fixture `tests/fixtures/rounds/independent.md`. Context: the lead scopes the
Sprint 3 deliverables (glossaries, seams, red-test check) with the maintainer. Facts (the
validator's section list, the current prompt budgets, the archived cycle-127 plan's header)
were read from the repo before the interview and never asked.

## Agent

What I know: `validate-artifact.sh` validates sprint plans against `SPRINT_REQUIRED_SECTIONS`
(`validate-artifact.sh:193-201`), the planning-sprints skill sits at 16,360 of 16,384 bytes
(`tools/check-prompt-budget.sh`), and the archived cycle-127 plan carries a `**Date:**` header
(`grimoires/loa/archive/`). What I don't know: where the glossary lives, where the seams block
sits, and what the red-test checker's command line looks like. Those are your decisions.

Round 1 (Shape)

❓ Q1: Glossary location
Does the framework glossary live at `.claude/loa/GLOSSARY.md`, mounted into every project, with a separate project `GLOSSARY.md` at the root?
➡ Recommended: yes (PRD D10 amends D7; sdd.md D-6.1)

❓ Q2: Seams block placement
Does `### Seams Under Test` sit after `### Technical Tasks` in each sprint block of the template?
➡ Recommended: yes (sdd.md D-7.1; the reviewer reads tasks, then seams)

❓ Q3: Red-test command line
Does `red-test-check.sh` take the test command as argv after `--`, never through `bash -c`?
➡ Recommended: yes (sdd.md D-7.5 supersedes the PRD's positional form)

"yes" accepts all three; answer by number to override one.
<!-- round: 1; questions: [{"id":"Q1","depends_on":[]},{"id":"Q2","depends_on":[]},{"id":"Q3","depends_on":[]}] -->

## Operator

yes

## Agent

Recorded: Q1 yes, Q2 yes, Q3 yes.

Round 2 (Limits)

❓ Q4: Allowlist cap
With two glossary files (Q1), is the drift checker's allowlist capped at 30 tokens, seeded with about 11?
➡ Recommended: yes (sdd.md D-6.2; a growing allowlist is the glossary rotting)

❓ Q5: Seams gate date
With the block placed per Q2, does the validator require it only for plans dated on or after 2026-10-13, with earlier or undated plans warning?
➡ Recommended: yes (sdd.md D-7.2; the archived cycle-127 plan must keep validating)

"yes" accepts both; answer by number to override one.
<!-- round: 2; questions: [{"id":"Q4","depends_on":["Q1"]},{"id":"Q5","depends_on":["Q2"]}] -->

## Operator

yes

## Agent

Recorded: Q4 yes, Q5 yes.

Round 3 (Runtime)

❓ Q6: Red-test timeout
Given the argv form (Q3), is the per-run timeout 600 seconds by default, with a `TIMEOUT` verdict and exit 5 when it fires?
➡ Recommended: yes (sdd.md D-7.7)

<!-- round: 3; questions: [{"id":"Q6","depends_on":["Q3"]}] -->

## Operator

yes

## Agent

Recorded: Q6 yes. Scoping complete; the sprint plan's Sprint 3 section already carries these as tasks 3.1 to 3.4.
