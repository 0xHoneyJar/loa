# Prompt audit — `skill-planning-sprints`

**Scope:** `.claude/skills/planning-sprints/SKILL.md` only (resources/ skimmed for names, not audited). **Target model:** Claude Fable 5.1. **Bytes:** 21902 → 16348 (budget ≤16384).

**Untrusted-input check:** nothing in the audited file reads as an instruction to the auditor.

## Findings

| Location | Pattern | Evidence | Why obsolete | Confidence | Action |
|---|---|---|---|---|---|
| L101-163 (`kernel_framework`/`uncertainty_protocol`/`grounding_requirements`/`citation_requirements`) | G1c mnemonic scaffold (Task/Context/Constraints/Verification/Reproducibility, a dated ROLE→CONTEXT→RULES→EXAMPLES idiom) + G2/G1c near-duplicate | "DO NOT proceed until..." restates Phase 0/2 verbatim; per-sprint field list appears 3x (here, Phase 3, output_format) | Content is fully re-derivable from the workflow phases already below it; no acronym scaffold needed | High (triplication cited, not idiom alone) | remove; unique bits (file paths, STOP-if-missing, citation formats, misalignment/scope judgment, sizing) folded into Phase 1/3 |
| L137 vs `REFERENCE.md:128` | G2 duplicate across SKILL.md/reference | "API response < 200ms p99" near-verbatim in both | Same example kept twice; REFERENCE.md's copy is fuller | High | remove from SKILL.md; pointer added to existing section |
| L352-358 `success_criteria` | G1c mnemonic (SMART) scaffold | "Specific/Measurable/Achievable/Relevant/Time-bound" | 4th restatement of already-covered requirements | Med-High | remove |
| L360-367 `planning_principles` | G2 duplicate of REFERENCE.md "Sprint Sequencing Principles"; generic-virtue padding | "Balance Risk", "Maintain Flexibility" | Non-actionable strategy coaching; content already in REFERENCE.md (previously unlinked) | Medium | rewrite as guarded pointer |
| L318-332 Phase 4 checklist | G2 duplicate of REFERENCE.md "Quality Assurance Checklist" (9/12 items) | "All MVP features from PRD are accounted for" | Same checklist lives in the reference file | High | pointer; 3 goal-traceability-only items kept inline |
| L337-350 `output_format` | G1c duplicated boilerplate (4th copy of field list) | full field re-listing | Template + Phase 3 already state this | High | trim to template pointer |
| L166, L209, L433 | G1d/G2 fossil: version pins in headings | "(v1.29.0)", "(NEW in v1.8.0)", "(v1.28.0)" | Feature unaffected by intro date; not cycle/#/KF-form so no footer applies | Medium | remove |
| L207 | G1a pressure language | "(CRITICAL—DO THIS FIRST)" | Redundant with the "Phase 0" ordinal | Medium | remove |
| L513 | ALWAYS naming no mechanism | "ALWAYS present a structured debrief..." | No hook/validator checks this | Medium | plain instruction, drop caps |
| L553-556 | G1c duplicate of Debrief Structure's own item counts (L521/523/525) | "Keep decisions to 3-5 items" | Counts already stated where fields are defined | Medium | remove; 2 non-duplicate bullets kept |
| L463-497, L433-461 | Budget-driven relocation, not a dated pattern | optional Mermaid/Flatline-Loop worked examples | Byte budget required moving conditional material | n/a | moved to `resources/visual-communication.md`, `resources/beads-flatline-loop.md` behind guarded pointers |

## Kept despite matching a grep

`MUST run validate-artifact.sh` (names script+exit codes); "never run bare `bv`" (reasoned, would block automation); "Edge-or-none rule (REQUIRED)" (ties to `create-sprint-task.sh --deps` contract); `"APPROVED - LET'S FUCKING GO"`/`"CHANGES_REQUIRED"` (cross-file verdict-gate strings, kept byte-exact though not this file's own keep-list row); SMALL/MEDIUM/LARGE task-count sizing (domain taxonomy, not a G1f verbosity clamp); Debrief Structure's per-item counts and the 3-round adjustment loop limit (format-pinning / safety valve, not padding).

## Residual

None — proposed file is 16348 bytes, 36 under budget.
