# Prompt audit report — `protocol-beads-integration`

**File**: `.claude/protocols/beads-integration.md` · **Target model**: Claude Fable 5.1
**Assumptions**: scope is this file only (per brief). The file has zero API-request-construction content (no thinking/effort/tool_choice/prefill/sampling params), so Group 1b/4 don't apply — it's a CLI-tool (`br`/beads_rust) reference manual, audited under Group 1c/1d/2.
**Byte count**: 10467 → 9439.

## Findings

| Location | Pattern | Evidence | Why obsolete | Confidence | Action | Keep-list check |
|---|---|---|---|---|---|---|
| L217–244 vs L359–363 | 1c/2 duplicated boilerplate + contract disagreement | `br sync --import-only 2>/dev/null \|\| br init` (L222) vs `br init 2>/dev/null \|\| br sync --import-only` (L362) | Same "session start" step given twice, fallback order reversed; two more of its steps exactly restate `/implement`/`Session End` in "Integration with Loa Workflows" | High | remove `### Sync Protocol for Loa Agents`; move its one unique step (`After Git Pull`) into Integration | item 8: duplicates disagree, so consolidation is warranted |
| L412–437 | 1c duplicated boilerplate | `## Quick Reference Card` restates the same commands a third time, incl. `br create ... -p 2 --json` — a flag spelling used nowhere else (Command Reference documents only `--priority`) | Third restatement of the same ~7 commands; adds its own contract drift instead of removing it | High | remove | item 8: `-p 2` vs `--priority` is a real disagreement |
| L281–302 | 1c row 1 — step choreography for a judgment task | 5-step numbered script for "when issue state is ambiguous" | Order doesn't matter for this judgment call; the choreography is pure overhead | Medium-High | rewrite to one paragraph, commands kept verbatim | no keep-list row covers this file; `NEVER fabricate` kept per item 5 |

## MUST/NEVER/ALWAYS

Nothing deleted. `NEVER fabricate` (L302) kept, restated in prose — no enforcing hook, but names a real current failure mode (ID hallucination), so item 5 applies. Philosophy's four NEVER/ALWAYS lines (L13–16) left untouched — see below.

## Kept despite a grep hit

- L13–16 (`NEVER executes git commands` / `auto-commits` / `background daemons` / `ALWAYS requires explicit sync`): density grep flags this, but these describe what the `br` binary itself does, not agent directives — context the agent needs. Unchanged.
- Storage-Architecture tree and Sync-Model diagram restate the DB/JSONL relationship already in the "Key Principle" prose and "Sync Commands" table — but the three agree, so item 8 keeps them.
- The `jq` examples and `Label Commands` list are CLI reference syntax, not few-shot behavioral examples (1c's over-indexing row targets the latter).

## Untrusted input

None found — nothing in the file reads as an instruction to the auditor.

## Residual above target

Target ≤7326 bytes; proposed is 9439, 2113 over. ~85% of this file is CLI contract material (8 tables, 9 command/config blocks) that Step 3 and keep-list item 4 protect, and it has none of the API-level scaffolding Fable 5.1 migrations usually remove. The two method-citable defects present are now fixed. Remaining candidates (ASCII diagrams, jq/label lists) either repeat non-disagreeing reference data (item 8 says leave alone) or are contract detail the method forbids cutting on byte count alone — so I stopped rather than propose an uncited cut.
