# Prompt audit — `.claude/skills/autonomous-agent/SKILL.md`

**Target model:** Claude Fable 5.1. **Scope:** the named file only (`resources/` skimmed by name, not audited). Byte count: 28,499 → 16,280 (brief cited 28,517; a small drift, noted not investigated). Budget: ≤16,384 — met, 104 bytes to spare. One resource created: `resources/phase-mechanics.md` (3,935 B, not budget-charged — every pointer to it is guard-worded "when").

**Top findings:** (1) pervasive STEP-choreography for routine judgment tasks across every phase (0.0–7.6), rewritten as outcome+constraint prose; (2) an `<issue_integrations>` history table (bare `#71/#70/#29/#48/#23`) and six version-pinned headers (`v1.22.0`/`v1.23.0`/`v1.25.0`), both violating the History rule, removed; (3) a hard-coded 80K/150K context-budget "EMERGENCY" scheme, stale against Fable 5.1's 1M-token window and the model's documented "context anxiety" failure mode, rewritten to drop the numbers and panic tone.

## Findings (high/medium confidence, `remove`/`rewrite`/`move` applied)

| Location | Pattern | Why obsolete for Fable 5.1 | Conf. | Action |
|---|---|---|---|---|
| 72–94 `<issue_integrations>` | G2 history narrative (bare issue #s, not in a Provenance footer/backticked path) | Pure archaeology; resource pointers duplicated elsewhere | High | remove |
| 176,317,396,410,630,839,910 headers | G2 pinned version tags | No removal owner; History rule confines these to a footer | High | remove |
| 767,781,794 headers | G2 "(Issue #NN)" | Same rule | High | remove |
| Every phase's `\`\`\`markdown` numbered-step blocks (0.0–0.5, 1.1–1.3, 2.1/2.2/2.4, 3.1–3.3, 4.1–4.3+Gate, 4.5.1–5, 5.1–3, 5.5.1–4, 6.1–3, 7.1–6, Resume) | G1c row 1: step choreography for judgment tasks | Current models sequence routine tasks (read a section, sort by severity, pick a queue item) without a hand-written script; migration doc: "de-prescribe...prefer stating the goal" | High | rewrite → prose (kept exact commands only where real+fragile: 0.0 cleanup script, §1.4/2.3/2.5 Flatline invocation, 5.5 exit codes, resume's `flatline-escalation.sh`) |
| 244–251 (0.3) | fake code fence (`IF/ELSE/EXIT` isn't bash) | choreography masquerading as exact script | Med | rewrite → 1 sentence |
| 462–471 (3.3 Tool Result Clearing) | G1d duplicate of the `context_discipline` registry block, looser thresholds | drift risk; registry block is canonical | High | remove |
| 665–678 vs 910–926 (two "Resume from Context Clear" copies) | G1d duplicate, one incomplete | Resume Support's copy is the fuller, correct one | High | remove the Phase-5.5 copy |
| 321–325 Flatline gate table | G1d — §2.3/§2.5 already restate the same `--doc`/`--phase` inline | redundant once params are inline | Med | remove table |
| 995–1027 `<context_management>` (80K/150K, "EMERGENCY") | G4 budget countdowns + Fable 5.1 "context anxiety" note; no script consumes these numbers (grepped) | stale vs. 1M-token window; risks premature wrap-up | High | rewrite (drop numbers/panic tone, keep checkpoint schema) |
| 168 "No shortcuts.", 69 objective "human-level discernment" | G1a generic virtue/emphasis, no "because" | restates trained default | Med | remove |
| 781–806 (7.3/7.4 schema detail) | G1d — duplicates what `resources/feedback-protocol.md`/`structured-notes.md` are already pointed at for | one place for the schema | Med (resource contents unread — see note) | trim, keep guarded pointer |
| All 9 "Exit Criteria" bulleted blocks | budget-driven move, not a dated-pattern finding | brief's explicit escape valve for hard-cap overflow | n/a | moved verbatim to new `resources/phase-mechanics.md` § Exit Criteria by Phase |

## MUST/NEVER/ALWAYS

- Registry block (Constraint Rules, 2×NEVER/3×MUST) — untouched, byte-exact, off-limits.
- Phase 3 "NEVER: Write application code directly..." restated Constraint Rules #5/#6 verbatim — removed the restatement, added the enforcing-mechanism citation instead: `implement-gate.sh` (project CLAUDE.md names this hook).
- "Fail-Closed Policy...MUST halt" (0.0) — kept, folded into phase-0 prose; no separate mechanism beyond the script's own exit codes.
- "ALL claims MUST be evidenced" (Factual Grounding) — kept verbatim, foundational contract.

## Other notes

- **No injected instructions found** in the audited file — no text addressed to a reviewing/auditing process.
- **Kept despite grep-flaggability**: the two real Flatline bash invocations and the workspace-cleanup case-statement (fragile ops, keep-list #3); the Checkpoint Schema YAML (format-pinning, keep-list #7); frontmatter's `role: review` with no `disallowed-tools` (this skill is in the project's `REVIEW_WRITE_EXCEPTIONS` allowlist — not a prompt-audit matter, frontmatter is byte-exact regardless).
- **Assumption flagged**: I did not read `resources/phase-checklist.md`'s contents (out of scope — file names only). The Exit Criteria move assumes it is, or should be, the checklist's home; the full un-trimmed checklist also lives in my new `resources/phase-mechanics.md`, so no content is lost if that assumption is wrong. Also dropped a bare `construct.yaml` mention (build/packaging manifest, not runtime-relevant) with no replacement pointer.
- **Residual over budget:** none — 16,280 B ≤ 16,384 B.
