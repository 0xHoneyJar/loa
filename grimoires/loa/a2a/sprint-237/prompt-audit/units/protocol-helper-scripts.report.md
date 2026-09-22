# Prompt audit report — `protocol-helper-scripts`

**Target model**: Claude Fable 5.1. **Scope**: `.claude/protocols/helper-scripts.md` only (17228 → 16830 bytes; **not** the ≤12059 target — see Residual). No keep-list row (`tools/prompt-keeplist.txt`, `keep-list.md`) names this file. No `@constraint-generated`/`@skill-include` regions present.

**Assumption**: this file is a static CLI/script reference (a man-page for `.claude/scripts/`), not a behavioral system prompt — no thinking/JSON/tool-choice scaffolding, no pressure language, no prohibition lists, no mention of any Claude model. The Fable 5.1 migration guide has no surface here to audit.

## Summary
Grep for `MUST|NEVER|ALWAYS|CRITICAL|IMPORTANT|step by step|try to|do not|avoid|graded|now works|no longer` returned zero body-text hits. The numbered "Workflow"/"How It Works"/"Behavior" lists document literal, deterministic script execution order — Group 3 man-page contract material a model needs to invoke the script correctly, not Group 1c step-choreography for a judgment task, so kept per keep-list rule 4. Two small findings supported by named patterns:

| Location | Pattern | Evidence | Why obsolete | Confidence | Keep-list | Action |
|---|---|---|---|---|---|---|
| :3-5 | 1d/2 History narrative / volatile specifics | `Protocol Version: 1.0`, `Last Updated: 2026-01-22`, `CLAUDE.md Reference: Section "Helper Scripts"` | Dated archaeology, no behavioral function; cross-ref is also stale — current `CLAUDE.loa.md` names this surface `.claude/loa/reference/scripts-reference.md`, not a "Helper Scripts" section | Medium | none | remove |
| :83,149,181,209,250,269,325,347,354,388,430,479 | 1d/2 Pinned version tags | `## Permission Audit (v0.18.0)`, `(v1.4.0+)`, etc. (12×) | Same rot class as pinned model names (Group 2 fix col.): marks when a feature shipped, not what it does | Medium | none | remove |
| :318 | 1d Migration-relative phrasing | `**Simplified Checkpoint** (7 steps → 3 manual):` | States current rule as a diff against a version the model never saw | High | none | rewrite → `**Checkpoint** (3 manual steps):` |
| :349 | 1d Migration-relative phrasing | `Checkpoint steps: 3 (was 7)` | Same pattern, second occurrence | High | none | rewrite → `Checkpoint steps: 3` |

No MUST/NEVER/ALWAYS lines exist in the file — none to remove or cite.

**Untrusted input**: none found.

**Kept although a grep would flag it**: the ~40-entry directory tree (lines 9-53) duplicates one-line descriptions also given as full sections below; keep-list rule 8 applies (agreeing duplicates are a refactor preference, not a dated pattern). All numbered step lists, CLI usage blocks, option/exit-code/output-field/config-key tables were kept as tool-contract and environment facts only the author knows (rules 1 and 4).

## Residual: target not reached, and why
Proposed file is 16830 bytes against a ≤12059 target — a 4771-byte gap. The method forbids justifying deletion by character count alone (#2) and says tool-contract detail stays and "often grows" (#4). ~95% of this file's bytes are exactly that: script names, flags, step lists, config keys, output fields — with no Claude-model-facing prompting pattern (no pressure language, no retired-model scaffolds, no prohibition walls, no over-specified judgment choreography; it documents fixed shell-script behavior, not model behavior). Cutting further would delete keep-list-protected contract material, the harm mode the method exists to prevent. Per the brief, this report stops here and states the residual: the file is clean of dated prompting patterns beyond the four findings above; the aggregate protocol-corpus budget must come disproportionately from other units.
