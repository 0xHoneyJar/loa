# Prompt audit report — `protocol-flatline-protocol`

**Scope**: `.claude/protocols/flatline-protocol.md` only. **Target model**: Claude Fable 5.1.
**Bytes**: 11370 → 7942 (target ≤ 7959; met).
**Keep-list**: no row in `tools/prompt-keeplist.txt`/`keep-list.md` matches this file's path — no byte-exact obligations apply; no `@constraint-generated`/`@skill-include` markers present.
**Untrusted-input check**: nothing in the file reads as an instruction directed at the auditor.

This is a README for the multi-model (Opus/GPT) review subsystem, not a Claude Fable 5.1 request-construction surface — it configures *other* models' calls, so Group 1b (thinking/prefill/tool_choice) doesn't apply. Findings are Group 1c/1d/2 (over-specification, fossils, brittle-doc duplication) plus one History-rule fix.

## Findings (highest confidence first)

| Location | Pattern | Evidence | Why obsolete | Confidence | Action |
|---|---|---|---|---|---|
| L316-319, L339-342 | Group 2, exact duplicate | Troubleshooting's "API key not configured" and `auth_expired` fixes repeat the identical `export`/`--setup-auth` lines already given earlier in the file | Verbatim duplication, no unique content | High | remove, replace with same-section pointer |
| L57 | History rule | `primary: opus # ... (alias; retargeted cycle-082)` | Bare `cycle-NNN` token in rule text, not a backticked path or footer | High | move to new `## Provenance` footer |
| L309 | Group 1d, "now" phrasing | "The orchestrator **now** handles markdown-wrapped JSON automatically" | Migration-relative phrasing implies a phantom prior state | High | rewrite: drop "now" |
| L12-34 | Group 1c, decorative formatting | boxed ASCII architecture diagram | ~2400 of 11370 bytes were box-drawing/padding chars (3 bytes/char UTF-8) carrying no info beyond available prose; this file is demand-loaded on every use | Medium | rewrite as 4-bullet list; all phase/call/threshold facts preserved |
| L92-134 | Group 2, duplicated info ("one place") | Quick Start's step 4 and End-to-End Workflow's Step 2 showed the identical review command twice; Step 3 restated the diagram's HIGH_CONSENSUS/DISPUTED/BLOCKERS/LOW_VALUE classification a 3rd time | Same command/classification repeated 2-3x | Medium | merge Quick Start + End-to-End into one `## Workflow`; classification now cross-references Architecture, keeping the one net-new fact (LOW_VALUE is logged) |
| L141-176 | Group 1c, choreography for a one-time, obvious action | "The auth setup: 1. Opens a browser... 4. Close browser... 5. Session saved to..."; "Create a Knowledge Notebook: 1. Go to... 4. Copy notebook ID" | Narrates predictable UI/browser behavior; no decision points | Medium | collapse each to one sentence; exact commands kept verbatim |
| L179-187 | Group 2, duplicated schema | second YAML block repeating `flatline_protocol.knowledge.notebooklm.*` keys already shown under Configuration | Same keys, same meaning, second copy | Medium | replace with a prose pointer to the one schema block |
| L346 | Group 1c, generic virtue / already-stated rule | Security Considerations: "API Keys: Store in environment variables, never commit to repo" | Restates a trained default and this repo's own project-wide rule (`zone-state.md`); nothing enforces it specifically here | Medium | remove; the two file-specific security facts (auth storage path, external-API document transmission) are kept |
| L293-301 | Group 2, volatile specifics | Cost Estimation table: `~$0.50-0.80`, `~$0.60-1.00 per document` | Dollar figures tied to model pricing rot untracked; distinct from the enforced, non-rotting `--budget` cap kept in CLI Reference | Medium | remove in full (a stale estimate is worse than none) |

## MUST/NEVER/ALWAYS

No `MUST`/`NEVER`/`ALWAYS`/`CRITICAL`/`IMPORTANT` shouting outside JSON example payloads. The file's one plain "never" (removed above) named no enforcing mechanism and duplicated a rule already stated project-wide.

## Deliberately kept though a grep would flag it

All CLI flag tables (Orchestrator/Model Adapter/Scoring Engine — Group 3 protects tool contract detail); the full Output Format JSON (format-pinning example, keep-list item 7); the Scoring Rubric table; the Document Privacy and NotebookLM-auth bullets in Security Considerations (non-obvious, file-specific facts). Also left untouched: the header/diagram/CLI-enum use of `GPT-5.2` and `Claude Opus 4.7`, even though the header's "GPT-5.2" doesn't match Configuration's default secondary model (`gpt-5.3-codex`) — a plausible doc-accuracy bug, but about which *external* model Flatline calls, not a dated Claude-prompting pattern, so it's flagged (low confidence) rather than edited.

## Residual / caveat

Target met. One judgment call worth naming: cutting the Cost Estimation table trades keep-list item 1 ("context is never cruft") against Group 2's volatility warning. It was cut as speculative and unenforced, superseded practically by the `--budget` cap. If wrong, the minimal fix is one non-numeric sentence ("cost scales with document size; cap it with `--budget`"), not restoring the dollar figures.
