
**Assumptions**: Scope = `.claude/skills/discovering-requirements/SKILL.md` only (resources read for routing/dedup context, not audited). Target model = Claude Fable 5.1. Byte count below is a manual estimate — I have only Read/Grep/Glob, no shell access to run `tools/check-prompt-budget.sh`; please verify mechanically.

**Byte count**: 28,610 → ≈15,950–16,300 (estimated) vs 16,384 budget.

**Untrusted input**: none found — the file is legitimate skill body text, nothing addressed at the auditor.

**Top findings**: an un-wired "Construct Override (Future — RFC #379)" stub nothing consumes; a `<kernel_framework>` block duplicating `<workflow>` almost line-for-line; a 113-line Phase-0.5 codebase-grounding block (brownfield-only) that was kept fully inline.

| Line(s) | Pattern | Evidence | Why obsolete | Conf. | Keep-list |
|---|---|---|---|---|---|
| 108–116 | 1d Fossil / History rule | `Construct Override (Future — RFC #379)` | Nothing consumes `trust_tier`/`BACKTESTED` (grepped); bare `#379` not in Provenance/backtick | High | none |
| 90–106 | 1a/1c Pressure+prohibition list | `(CRITICAL)` + 6×DO NOT | No hook enforces `no_infer`; rewritten as one prose paragraph, same substance | High | none |
| 208–236 | 1c/1b duplicated boilerplate | `<kernel_framework>` Task/Context/Constraints | Fully restates `<workflow>`; one non-dup fact (integration-context.md) folded into Step 1 | High | none |
| 238–350 | 2 Conditional bulk | `<codebase_grounding>` full block | Brownfield-only path; moved to REFERENCE.md §Codebase Grounding, guarded pointer kept | High | none |
| 396–438 | 1c Example over-indexing | `<context_map>` 43-line XML worked example | Internal-only categorization step; condensed to one descriptive paragraph | Medium | none |
| 450–470 | 1c Example over-indexing | "product-market fit" worked example | Single gold example biases every session; prose instruction already states behavior | Medium | none |
| 472–496 | 1c Step choreography | IF/ELSE lookup logic | Rewritten as 4-row decision table (method's own recommended fix) | Medium | none |
| 515–548 | 2 Duplicated w/ resources | Phase topic bullets + 3-row EARS table | REFERENCE.md §Discovery Phase Questions and ears-requirements.md already hold fuller versions | High | none |
| 446, 594 | 2 Volatile version tags | `(v1.42.0)` ×2 | Pinned versions rot; feature description unaffected by removal | High | none |
| 615–644 | 3 Worked example | Full `Task(...)` prompt template | LARGE-context conditional path; template moved to REFERENCE.md | Medium | none |
| 655–663 | 1c/1d Grader-vocab/unenforced | `<success_criteria>` SMART list | Not measurable in-session; every item duplicates other sections | Medium | none |
| 665–670 | 1c Padding | "Never assume → Always cite or ask" | Restates registry-protected factual_grounding mandate | Low-Med | factual_grounding untouched |
| 687–737 | 1c Bullet wall / conditional | Full Debrief numbering+YAML+Adjust flow | Format-sensitive strings kept byte-exact in REFERENCE.md §Post-Completion Debrief; SKILL.md keeps a summary only | Medium | quoted strings preserved |
| 690 | MUST/ALWAYS | validator MUST + debrief ALWAYS | MUST kept (mechanism: validate-artifact.sh). ALWAYS dropped (no mechanism named) | High/Med | script name preserved |
| 58, 62 | dead config (flag only) | `discovery_style`, `show_work` | Grepped: unreferenced anywhere else in the file | Low | — |
| 141 | 1c Generic-virtue hedge | trailing "never force philosophical connections" | Judgment caveat the model doesn't need spelled out; mechanism (field names) kept | Low | Lore fields kept |

**Registry/skill-include blocks kept byte-for-byte**: prompt_enhancement_prelude, discovering_requirements_grants, integrity_precheck, factual_grounding, context_discipline, trajectory_logging; frontmatter byte-exact.

**Deliberately kept despite a grep match**: MANDATORY headers (registry-protected); `<zone_constraints>` prose (no hook enforces the frontmatter `zones:` block for this skill — the prose is the only enforcement surface; method says never delete a zone rule); Debrief's quoted format strings/AskUserQuestion schema (format-pinning, keep-list #7, now in the resource); the three interview-config tables (already the method's recommended compact form — only separators/cell wording trimmed, structure untouched).

**Mechanical, no-information-loss trims applied everywhere**: table separator rows shortened to minimal `|---|---|` form (~10 tables) — pure syntax, renders identically.

**Residual**: manual estimate lands just under budget with a thin margin (~400 bytes). If the mechanical check reports over, next cuts in order of lowest risk: Debrief's two summary sentences, Persona's Lore-Integration example clause, Mode-Behavior/Input-Style table wording.

