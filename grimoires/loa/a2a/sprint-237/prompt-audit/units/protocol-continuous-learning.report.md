# Prompt audit — `.claude/protocols/continuous-learning.md`

**Target model**: Claude Fable 5.1. **Scope**: this file only. It's a protocol, not a skill — no K-41/K-42 keep-list rows apply, no keep-list row names this path, and no `@constraint-generated`/`@skill-include` markers are present (grepped, none found).

**Bytes**: 13,905 → 7,813 (−43.8%; target ≤9,733 met, 1,920 bytes of margin — no residual).

## Findings

| Location | Evidence | Pattern | Why obsolete for Fable 5.1 | Confidence | Action |
|---|---|---|---|---|---|
| L172–188 | `### Pre-commit Validation (Recommended)` bash script | Group 1d, unenforced instructions | Verified: `.claude/hooks/pre-commit` is a directory holding only `bb-dist-check.sh`; nothing in `.claude/scripts` or the hooks tree wires this snippet in, and it's self-labeled optional. Duplicates the declarative Zone Compliance table above it with a worked script instead of a rule. Nothing enforces it, nothing would miss it. | High | remove |
| L11–79 | ASCII flowchart (DISCOVERY DETECTED → GATE 1–4 → NOTES.md Cross-Reference → SKILL EXTRACTION) | Group 1c row 1 (step choreography for a judgment task) + row 4 (heavy formatting) | The GATE 1–4 boxes are a fully redundant, less-detailed restatement of the `## Quality Gates` tables directly below. Fable 5.1 is explicitly de-prescribed against migrated step-by-step scaffolding for judgment calls (`METHOD-fable-5.1-migration.md` § Long-running agent recommendations). The two boxes carrying unique contract text (NOTES.md dedup disposition; the exact output path + `skill-template.md`) are not deleted — rewritten as two prose sentences, so no contract text is lost. | High | rewrite |
| L3, L289 | `(v0.17.0)` header pin; footer `*Protocol created … (v0.17.0)*` | Group 2 volatile version numbers; Group 1d history/pinned-version fossils | Verified via `git log --follow`: this file was introduced in the commit tagged `feat(v0.19.0): … Continuous Learning (#33)` — the in-file `v0.17.0` claim was already wrong at introduction and unchecked since. | Medium | remove |
| L154 | `**CRITICAL**: Extracted skills MUST NOT write to System Zone.` | Group 1a pressure language (`CRITICAL:` with no adjacent "because") | An enforcing mechanism exists (`zone-system.md` write-guard hooks, named in `CLAUDE.loa.md`), so the rule is **kept** — only the shout is removed and the mechanism is cited in its place. | Medium | rewrite |

## MUST/NEVER/ALWAYS inventory

Only one such line exists in the file (L154, above) — kept, rewritten to cite `zone-system.md` instead of shouting.

## Flagged, not fixed

- `Research Foundation: Voyager (2023), CASCADE (2024), Reflexion (2023), SEAgent (2025)` (L5) — reads like a history narrative by analogy (design provenance, not an instruction), but no Group row names academic citations and no Fable-5.1-grounded reason applies. Low confidence; kept unchanged.
- `## Skill Lifecycle` arrow diagram duplicates the `### States` table below it, but the two don't disagree and the diagram is static reference data, not behavioral choreography (keep-list #8: dedup only when duplicates disagree). Kept unchanged.
- `### Pruning Criteria` bullets overlap `prune_after_days`/`prune_min_matches` in the Configuration Reference YAML but add one criterion (superseded-by-newer-skill) the YAML lacks — not a full duplicate. Kept unchanged.

## Untrusted input

Grepped the audited file for injection-style phrasing (`ignore`, `disregard`, "you are now", "as an AI", "system prompt", …) — no matches; nothing in the file addresses the auditing agent.

## Kept although a grep would flag it

Both `## Quality Gates` tables (20 rows, 4 gates) survive byte-for-byte — varied, labeled-illustrative examples calibrating a project-specific judgment call, not restatements of trained defaults (keep-list #1/#7). The `Trajectory Logging` JSONL schema and `Configuration Reference` YAML survive byte-for-byte as data/tool contracts (keep-list #4), as do the `Phase Gating` and Zone Compliance path tables.
