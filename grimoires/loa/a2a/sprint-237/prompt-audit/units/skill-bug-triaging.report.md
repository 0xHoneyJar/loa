# Prompt audit report — `skill-bug-triaging` (lead-authored)

**Target model**: Claude Fable 5.1. **Bytes**: 19358 → see gate output (target 16384). Generated regions (input_guardrails, prompt_enhancement_prelude) byte-identical; keep-list rows K-41/K-42 hold; `inputs:` manifest kept for skill-inputs-manifest.bats.

| Line | Pattern | Evidence | Action |
|---|---|---|---|
| 76-84 | 1c duplicated boilerplate; 1a prohibition wall without mechanism | `## Constraint Summary` six NEVER/ALWAYS lines restating the phase rules (and CLAUDE.loa.md's `/bug` NEVER row) | removed; each rule stays where its mechanism is (eligibility check, PII redaction, atomic write, test-runner HALT) |
| 111-134 | 1c triplicated statement | Phase 0 `### Procedure` pseudo-code and `### Failure Modes` table restate the Required/Optional tool tables | removed; tables + connectivity check carry the rule |
| 211-219 | 1c example over-indexing | five calibration rows for a three-branch scoring rule | two rows kept (one ACCEPT, one REJECT) |
| 229-235, 290-310, 346-352 | 1c duplicated boilerplate | per-phase `### Failure Modes` / `### Procedure` blocks restating the algorithm above them | folded into the algorithm (reproduction_strength, abandon, contradictory answers) or one sentence |
| 333-334 | 1d dated rationale | `smaller models (e.g., 3B parameter fast-code)` | rationale kept model-agnostic |
| 439-448 | 1d history narrative inside a step | the collision-wart story behind `next-bug-sprint-id.sh` | contract stated in three lines, test named |
| 545-552 | 1c restated postlude; stale `3+ quality gates` | hand-written retrospective postlude | one sentence pointing at the continuous-learning gates |

Kept: tool tables, PII patterns and allowlist, signal scoring, disqualifiers, exception policy, gap algorithm, fix-hint schema, bug-id rule, state schema and transitions, micro-sprint steps incl. the `validate-artifact.sh` MUST, ledger registration, handoff banner. Untrusted input: none.
