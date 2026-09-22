# Prompt audit report — `skill-translating-for-executives` (lead-authored)

**Target model**: Claude Fable 5.1. **Bytes**: 21787 → see gate output (target 16384). Generated regions (prompt_enhancement_prelude, context_discipline) byte-identical; keep-list rows K-41/K-42 hold.

| Line | Pattern | Evidence | Action |
|---|---|---|---|
| 5-7 | 1d history token in rule text | frontmatter comment `cycle-120 audit: …` | one-line reason without the token |
| 36, 442, 565, 576 | 1d version pins | `(Enterprise-Grade v2.0)`, `Translator: v2.0.0`, `- v2.0`, `(v2.0)` | removed |
| 39-43 | 1a persona inflation + narrative | `elite … 15 years of experience`, `managed scaffolding framework inspired by AWS Projen, Google ADK…` | the auditor framing (Ghost Assets / Undisclosed Liabilities) kept as one paragraph |
| 52-101 | 1c duplicated mechanism | hand-rolled SHA loop and banner reproduce `preflight.sh check_integrity` (Phase 0 calls it) | one paragraph: config key, strict/warn/disabled behaviour, resolution steps |
| 106-117 | 1c ASCII box | truth hierarchy box | four-item list |
| 176-185 | 1c duplicated checklist | grounding checklist restates the self-audit's G1–G5 | removed |
| 187-232 | 1c duplication | orchestrator box restates Phase 3; clearing example and attention table restate the Context Discipline include | one paragraph pointing at Phase 3 and the include |
| 483-546 | 1c example over-indexing | two full worked translations | moved to `resources/REFERENCE.md` §Translation Examples behind a guarded pointer |
| 548-562 | 1c restated success list | Definition of Done repeats the workflow and self-audit | removed |
| 564-617 | 1c/1d | diagram section with `Preview URLs are no longer generated` migration note and duplicated diagram tables | one paragraph: required diagrams, format, theme key, PNG export |

Kept: truth-hierarchy conflict resolution and terminology, citation formats, assumption tagging, audience matrices, the eight-phase workflow incl. the `validate-artifact.sh` MUST, health-score formula, self-audit tables and the translation-audit.md template. Untrusted input: none.
