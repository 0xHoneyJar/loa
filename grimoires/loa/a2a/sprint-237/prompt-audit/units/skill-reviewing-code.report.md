
**Assumptions.** Scope: `.claude/skills/reviewing-code/SKILL.md` only (its `resources/` skimmed for routing, not audited). Target model: Claude Fable 5.1, per `METHOD-fable-5.1-migration.md`. Byte budget: ≤16,384 (today 32,398).

**Byte count.** Before: 32,398. After (hand-count, no shell access to verify): ≈24,070, savings ≈8,330 bytes. This leaves a **residual overage of ≈7,690 bytes above the 16,384 target** — see "Residual" at the end; I did not manufacture further cuts to close it.

**Untrusted input found**: none — the file contains no text addressed to me as an auditor.

## Findings

| Line(s) | Pattern (group/row) | Evidence | Why obsolete for Fable 5.1 | Confidence | Keep-list check |
|---|---|---|---|---|---|
| 205–250 `<kernel_framework>` | Group 1b (ROLE→CONTEXT→RULES→EXAMPLES scaffold) + Group 1d (patch accretion/duplicate boilerplate) | Full N-C-L-E-R block (Task/Context/Constraints/Verification/Reproducibility) | Every bullet is a verbatim duplicate of `<objective>`, `<adversarial_protocol>`, `<citation_requirements>`, or Workflow Phases 1–4 (verified line-by-line). Two items were **not** duplicated (AC-Verification auto-fail rule, Discord/Linear link check) — relocated to Phase 4 and `<citation_requirements>`, not deleted | High | No keep-listed string (K-25..30) is inside this block |
| 225 | History rule | `(cycle-057, Issue #475)` | citation outside a Provenance footer | High | moved to new footer |
| 118–128 `### Challenge Categories` | Group 2 (model already knows) + Group 1c (bullet wall, no "because") | table of generic review questions | Standard senior-engineer review heuristics with no project-specific content | Medium | none affected |
| 252–258 `<uncertainty_protocol>` | Group 2 (duplicate across files) | "Document assumptions… ask before implementing" | Restates the always-loaded CLAUDE.loa.md "Think Before Coding" Karpathy principle, in context every turn regardless of skill | Medium | none affected |
| 260–274 `<grounding_requirements>` | Group 1d (duplicated boilerplate) | reading-order list 1–6 | Identical, item-for-item, to Workflow Phase 1; item 7 duplicates Phase 2 item 1; only item 8 (qmd query) was unique — folded into Phase 1 | High | none affected |
| 285 | Group 1a (pressure language, redundant with ordinal) | `(CRITICAL—DO THIS FIRST)` | "Phase -1" already signals first | Medium | none affected |
| 304 | Group 1a (same pattern) | `(FIRST)` on "Phase 0" | ordinal already conveys sequence | Medium | none affected |
| 339 | History rule | `(#1086)` in a header | issue citation outside Provenance footer | High | moved to footer |
| 370–407 `Phase 2.5` | Byte-budget "move" (conditionally-needed mechanism, gated by a config flag) | full bash/JSON/table mechanics | Only relevant when `flatline_protocol.code_review.enabled: true`; moved verbatim to `resources/ADVERSARIAL-REVIEW.md`, fence name + remedy kept inline (`adversarial-review-gate.sh`, `LOA_ADVERSARIAL_REVIEW_ENFORCE=false`) | High (self-classified move) | gate name/override preserved in SKILL.md itself |
| 472–512 `<parallel_execution>` | Group 1d (duplicate) + move | "When to Split" list duplicates Phase -1's table; Task() template + Consolidation moved to `resources/PARALLEL-REVIEW.md` | Phase -1 already gates on the same thresholds one section earlier | High (dup) / n/a (move) | none affected |
| 532–538 `<success_criteria>` | Group 1c (generic virtues, SMART-acronym boilerplate) | Specific/Measurable/Achievable/Relevant/Time-bound | Restates content stated properly elsewhere; "Time-bound: completes within session" cuts against Fable 5.1's normal longer turns | Medium | none affected |
| 541, 581, 657 | Group 2 (version pin / history narrative) | `(v0.19.0)`, `(v0.16.0)`, `(v0.19.0)` | version tags with no ongoing value | High | none affected |
| 543 | Group 1a (stacked emphasis) | `**MANDATORY**:` under a header already titled "(Required)" | two markers for one fact | Medium | none affected |
| 603 | Group 1a (shout, no added info) | `**DO NOT APPROVE**` | header + table below already carry the constraint; kept the sentence, dropped bold-caps | Low | table + verdicts untouched |
| 663–685 `### Review Integration` | Group 1c (worked example the model doesn't need) | markdown template for writing up complexity findings | Not parsed by any script (unlike LOA-VERDICT trailer); Fable 5.1 organizes structured markdown without a shown template | Medium | none affected |
| 700 | History rule | `(#1012-adjacent)` | issue citation outside footer | High | moved to footer |
| 722–755 `<beads_workflow>` | Move (conditional: only when `br` installed) | full command/label reference | Moved to `resources/BEADS-WORKFLOW.md`, pointer kept | High (self-classified) | no keep-list hit |
| 641–653 checklists Red Flags | Group 2 (duplicated info across SKILL.md and reference file) | 6-item Red Flags list | Exact subset of REFERENCE.md's larger "Red Flags" section; pointer now names it explicitly instead of repeating | Medium | none affected |

**Deliberately kept although a grep would flag it:**
- `<zone_constraints>` (141–145): duplicates the frontmatter `zones:` YAML, but the brief's never-delete list names "a zone rule" explicitly — left untouched.
- `Karpathy Principles Verification` table (354–368): defines the `SIMPLICITY:`/`SURGICAL:`/`GOAL-DRIVEN:` feedback-tag vocabulary the YAGNI taxonomy reuses — unique, load-bearing.
- `<adversarial_protocol>` register ("You are not a rubber stamp. You are a rival.") — reasoned framing with a stated mechanism, not bare pressure language.
- `<documentation_verification>` / `<subagent_report_check>` tables — REFERENCE.md's own text says these "remain in the skill body" (a prior deliberate split). Moving them further would strand that comment and push a hard approval gate behind a conditional file-read; left in place.
- No API fossils, retired-model names, or scratchpad/prefill/JSON-forcing scaffolds found — this skill has none of the Group 1b/4 API-migration patterns.

**MUST/NEVER/ALWAYS removed or rewritten**: none removed. All either already cite their mechanism (`verdict-derive.sh`, `PreToolUse:Write` gate, `## Findings`/`## Issues` ban) and were left verbatim, or were pure duplicates of a cited rule elsewhere in the same file (kernel_framework `DO NOT` bullets), removed only because the cited rule survives intact at its other location.

**Residual above target (≈7,690 bytes) and why**: (1) six `@skill-include`/`@constraint-generated` regions plus frontmatter (≈5,500–6,000 bytes) must be copied byte-for-byte; (2) `<adversarial_protocol>` and Phase 5 carry the keep-list-protected LOA-VERDICT/entry-format contract verbatim and are already lean; (3) `<documentation_verification>` and `<subagent_report_check>` still hold real checklist/verdict tables (~1,400 + ~1,700 bytes) a prior edit deliberately left in the skill body per REFERENCE.md's own comments — re-moving them would strand that comment and risk hiding a hard gate behind a conditional read. If the lead wants the gap closed further: move `subagent_report_check`'s "Reports to Check" and "Non-Blocking Verdicts" tables (informational, not gates) to a new resource, leave "Blocking Behavior" inline, and update REFERENCE.md's stale comment in the same patch — I did not do this since it touches a second file's prose outside this unit's scope.



## Lead addendum — post-A/B iteration (2026-09-22)

Arm B (tree `4f13f15c`) failed the review-recall gates: anchored recall 0.958 → 0.820 and clean-PR critical+high 0 → 0.33. Diagnosis from the artifacts: arm B described the planted defects but cited a neighbouring statement or a narrow line (`audit_envelope.py:462` for the anchor at 468; `semver-bump.sh:79` for 83) where arm A cited wide ranges (`462-473`, `80-94`) that swallow the anchor; on the clean PR, both arms found the same dotted-route heuristic and arm B rated it HIGH where arm A rated it MEDIUM. One iteration (`proposed7.md`): the Coverage block now asks for a citation of the failing statement itself, as a range when the defect spans lines, and states that `high` needs a nameable failing input or exploit path while a check that only might misfire is `medium`; the persona line, the Karpathy example and the fast-gate preamble are trimmed to pay for it (16,334 B). Arm B2 re-runs the review-recall suite on this tree; the audit and implement arms are unaffected by the change (auditing-security untouched) and are not re-run.
