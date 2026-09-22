# Audit report — `.claude/skills/simstim-workflow/SKILL.md`

**Assumptions**: scope = the named file only (its `resources/` skimmed for names, not audited). Target model = Claude Fable 5.1. Budget: ≤16,384B (`tools/check-prompt-budget.sh`).

**Bytes**: 26,152 → 16,212 (frontmatter + registry block copied byte-exact; K-41/K-42 `name:`/`description:` survive).

## Findings

| Location | Evidence | Pattern | Why obsolete | Conf. | Action |
|---|---|---|---|---|---|
| L52, L77 | `Users report confusion (#192)`; `PR #216 was rolled back...` | History rule (bare #NNNN in rule text) | Only survives in `## Provenance` footer or a backticked path | High | move→footer |
| L107, L150 | `(FR-3, cycle-048)`; `(cycle-045)` | History rule | Same | High | move→footer |
| L455/467/490/504 | `(v1.28.0)`, `(v1.25.0)` | Group 2 pinned-version narrative | Same class as pinned model names — degrades, adds nothing actionable | Med | remove→footer |
| L53–59 | worked "Correct behavior" dialogue + "if you feel the urge to plan" | 1c example over-indexing, dup of generated rules 1–2 below | Already stated as a NEVER rule; 2nd worked example adds no contract | Med | rewrite (1 sentence) |
| L116–127 | "phases will be skipped" ×2, bolded "**warning, not blocking**" | 1a pressure + 1c restatement of the quoted display string | Over-emphasizes a status the exact display string already carries | Med | rewrite |
| L161–162 | `Example: [0/11]... [0/8]... when none.` | 1c example over-indexing | Format already unambiguous from the template above | Med | remove |
| L176–181, 267–273, 371–377 | 6–7 step "guide user through X" lists (Discovery/Arch/Planning) | 1c judgment-task choreography + Group2 "explains what model knows" | No scripted checklist needed to interview for PRD/SDD/sprint content | High | rewrite→1 sentence ea. |
| L330 | `red_team.design_review.enabled: true` | Group 2 volatile specifics | Key doesn't exist; config + this file's own Preflight step 8 + `resources/phase-4.5-*.md` use `red_team.enabled`+`red_team.simstim.auto_trigger` | High | rewrite (fix key) |
| L336–361 | "Red Team Integration Status (cycle-047)" | 1d history narrative + migration phrasing + duplicate w/ **divergent** key | Duplicates content already correct elsewhere in-file, but with wrong key — disagreeing duplicates are removable | High | remove |
| L441 | `**CRITICAL**: Do NOT implement directly...` | 1a pressure, dup of generated rules 6/7 | Rule already stated w/ reasoning earlier in file | Med | rewrite→fold in |
| L496 (+dup in Resume Support) | `⚠️ WARNING: ...last resort...` | 1a pressure language | "escape hatch"/"bypasses validation" already convey risk | Med | rewrite |
| L201–254, 302–323, 398–419 | Flatline HITL template spelled out once, ref'd twice | Byte-budget move (long template) | 26,152B vs. 16,384B hard cap | — | move→`resources/flatline-hitl-review.md` |
| L592–751 Resume Support | ~5.4KB, conditional on `--resume` | Byte-budget move | Same | — | move→`resources/resume-support.md` |
| L550–588 Error Handling | ~1.1KB, conditional on failure/timeout/interrupt | Byte-budget move | Same | — | move→`resources/error-handling.md` |

## Untrusted input
No text reads as an instruction to the auditor; all imperative voice targets the executing agent, not me.

## Kept despite a grep hit
Registry block (9 rules, byte-exact, mechanism = `.claude/data/constraints.json` generator). Gibson epigraph (short identity flavor, no matching pattern). Cost section's `Opus 4.7/GPT-5.3-codex/Gemini 2.5 Pro` + "verified 2026-04-15" — cross-checked against `.loa.config.yaml.example` + 5 sibling skills, still the currently-configured Flatline reviewer set; describes 3rd-party tool cost, not target-model instruction, out of scope. All format-pinned UI templates (DISPUTED/BLOCKER prompts, resume banner, completion message) kept verbatim (rule 7). All-caps state enums (`COMPLETED`, `HALTED`, `SYNC_FAILED`) are wire values, not shouting.

## Note (out of scope, not fixed)
Constraint rule 3 and Preflight both reference a "Phase 6.5" with no corresponding phase section anywhere in the file — pre-existing gap, not a dated pattern; fixing it means inventing content.

## Residual
None. Final file 16,212B (172B headroom). Verified no `resources/*.md` pointer line matches the budget script's charge rule (imperative `read|load|source|include` without a guard word) — all use `see`/`Full procedure: →`/"Run the shared...procedure", so no resource is charged against the 16,384B cap.
