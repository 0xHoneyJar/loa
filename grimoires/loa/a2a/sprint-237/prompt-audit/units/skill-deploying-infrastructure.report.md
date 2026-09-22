
**Assumptions.** Scope: `.claude/skills/deploying-infrastructure/SKILL.md` only (resources/ skimmed, not audited). Target: Claude Fable 5.1. No embedded instructions targeting the auditor found in the file.

**Bytes.** Before: 29,313 B. After (SKILL.md only): ~9,000–13,000 B estimate — this session has no Bash access to run `tools/check-prompt-budget.sh`, so this is a manual line-count estimate, not a mechanical measurement; recommend the lead confirm with the script. New resource pointers use "See … for …" phrasing with no read/load/source/include verb, so none are charged against the budget per the script's own rule.

**Top findings:** (1) `<release_documentation_verification>` + `<e2e_verification>` are two near-duplicate ~90/160-line verification matrices (same CHANGELOG/README/test/build/security gates stated twice) → moved to new `resources/VERIFICATION.md`, replaced by one condensed gate paragraph — most of the byte reduction. (2) `<parallel_execution>`'s Decision Matrix + worked "Agent 1:/Agent 2:" dialogue, plus `<workflow>`'s "Phase -1" line-count thresholds, are step-choreography for a delegation judgment call Fable 5.1 is documented to handle well unscaffolded — collapsed into one paragraph in Workflow. (3) `<success_criteria>` duplicates `kernel_framework`'s Verification bullets near-verbatim plus two unsourced numeric ceilings ("within 120/30 minutes") that contradict `<uncertainty_protocol>`'s own instruction to ask the user for SLA — deleted, unique items (e.g. "Rollback procedure documented") folded into the surviving Verification list.

| Line(s) | Pattern | Evidence | Why obsolete | Conf. | Keep-list |
|---|---|---|---|---|---|
| 412-499, 575-734 | Group 2 duplication | two verification matrices, same gates twice | tax on every trigger, pure duplication | High | none — passed |
| 648-676 | Group 1c gold-output + Fable 5.1 "ground progress claims" | `Total tests: 156`… `2.3s` | invented numbers prime fabricated status reports | High | none — passed |
| 227-325 | Group 1c choreography/example + Group 1f threshold | Decision Matrix, Agent1/Agent2 dialogue, ">5 issues" | Fable 5.1 delegates reliably unscripted | High | none — passed |
| 177-201 | Group 1a pressure + Group 2 wrong degrees of freedom | "CRITICAL - DO THIS FIRST", ">5,000 lines MUST split" | hardcoded threshold for a judgment call | High | none — passed |
| 357-386 | Group 2 duplication + Group 1f numeric ceiling | SMART framework, "within 120 minutes" | duplicates Verification; ceiling contradicts ask-for-SLA elsewhere | High | none — passed |
| 529-550 | Group 2 duplication | Version Pinning vs line 168 Reproducibility | same fact, same example, twice | High | none — passed |
| 391, 555 | brief's byte-budget rule | "Load … from: resources/X.md" no guard word | script charges full resource size | High | none — passed |
| 40 | Group 1d identity-stub padding | "battle-tested… 15 years… network attacks" | roleplay CV beyond keep-list #9's one-line role | Medium | none — passed |
| 412, 576, 737 | Group 1d/2 version-pin fossil | "(v0.19.0)", "(v1.36.0)" | rules stated as current only | High | none — passed |

**MUST/NEVER/ALWAYS.** No hook/validator named for `<release_documentation_verification>`/`<e2e_verification>`'s "MANDATORY" or Workflow's "CRITICAL" — both rewritten plainly, substance kept (moved/condensed). The 9-line DO/DO-NOT `Constraints` list encodes real security/gating policy (keep-list #5) — kept, reframed into 3 prose bullets. The `@constraint-generated` block's own MUST/ALWAYS is protected registry content — untouched.

**Kept despite a grep hit:** `<uncertainty_protocol>`'s "Always choose security over convenience" (real security policy, not a stylistic tic). `@constraint-generated`/`@skill-include` MANDATORY/MUST/ALWAYS — protected registry text. `<zone_constraints>`'s "never edit" — a zone rule, never removed.

**Residual:** none expected; figure above is an estimate, no mechanical byte-check available this session.

