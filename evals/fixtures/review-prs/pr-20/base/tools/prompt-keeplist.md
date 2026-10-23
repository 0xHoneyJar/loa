# Prompt-audit keep list — cycle-124 Sprint 3 (FR-8, AC-8.3)

Companion to `tools/prompt-keeplist.txt` (machine-readable; read by `tests/unit/prompt-audit-keeplist.bats`). Written and committed **before** the first audit subagent is dispatched. Every deletion in a per-file audit report cites the keep-list check it passed; a patch that removes a keep-listed string is rejected by the lead gate before it is read.

**What the audit removes**: history narrative in rule text (cycle/PR/KF numbers outside a `## Provenance` footer), MUST/NEVER/ALWAYS where a hook or validator already enforces the rule (the citation replaces the shout), step choreography for judgment tasks, generic virtues, duplicated boilerplate, emphasis.

**What it never removes** (the classes below; ids map to the txt file):

| Id | File | Protected string | Why it stays |
|---|---|---|---|
| K-01 | CLAUDE.loa.md | Three-Zone row `System · .claude/ · NEVER edit` | the zone model is the mechanical boundary every hook assumes |
| K-02 | CLAUDE.loa.md | "Never edit `.claude/` … `.claude/overrides/`" | a rule and its remedy travel together |
| K-03, K-04, K-05, K-06, K-07 | CLAUDE.loa.md | the five `@constraint-generated` blocks (process_compliance_never / _always, task_tracking_hierarchy, merge_constraints, agent_teams_constraints) | registry-rendered; edited only through `generate-constraints.sh`; `prompt-audit-generated-blocks.bats` gates drift |
| K-08, K-09, K-10 | CLAUDE.loa.md | `LOA-VERDICT`, `verdict-derive.sh`, the one-way rule | the review/audit gate contract; the confidence dimension can never demote |
| K-11, K-12, K-13 | CLAUDE.loa.md | `audit_emit`, `lib/jcs.sh`, `UNTRUSTED` | agent-network L1–L7 universal invariants (prose-only, no mechanical twin) — collapse to the Reference-Files pointer paragraph, never delete |
| K-14, K-15 | CLAUDE.loa.md | `JACKED_OUT`, `sprint-plan-state.json` | run-mode state recovery after compaction (prose-only) |
| K-16 | CLAUDE.loa.md | `session-limit-capture.sh` | the session-cap remedy is the instruction |
| K-17 | CLAUDE.loa.md | `beads-health.sh` | beads-first health check (prose-only) |
| K-18 | CLAUDE.loa.md | `hooks-reference.md` | fence *documentation* may shrink; the pointer to the inventory and accepted bypass classes stays |
| K-19, K-20, K-21, K-22 | CLAUDE.loa.md | "Never simplify away", `loa:shortcut`, `simplicity_intensity`, `karpathy-principles.md` | the Karpathy kernel: floor, marker convention, intensity knob, rationale pointer |
| K-23, K-24 | CLAUDE.loa.md | `golden-path.sh`, the `/loa` table row | Golden Path table kept verbatim |
| K-25, K-26, K-27, K-28, K-29, K-30 | reviewing-code | `All good`, `LOA-VERDICT`, `verdict-derive.sh`, `"gate":"review"` example, `engineer-feedback.md`, `disallowed-tools:` | verdict contract, format-pinning example, output path, tool policy |
| K-31, K-32, K-33, K-34, K-35 | auditing-security | `APPROVED - LET'S FUCKING GO`, `LOA-VERDICT`, `verdict-derive.sh`, `auditor-sprint-feedback.md`, `disallowed-tools:` | same classes for the audit gate |
| K-36, K-37, K-38 | implementing-tasks | `reviewer.md`, `AC Verification`, `br close` | report path, the section `validate-ac-verification.sh` gates on, beads lifecycle |
| K-39, K-40 | run-mode | `JACKED_OUT`, `verdict-derive` | state machine names; the gate reads the trailer, not prose |
| K-41, K-42 | the 13 audited skills | `name:` / `description:` frontmatter | trigger and routing text |
| K-43, K-44, K-45 | Flatline personas | `confidence`, `"concerns"`, `score` | schema-bearing fields the wire schemas mirror (`wire-schemas-api-safe.bats` W5) |
| K-46 | prompt-audit-keeplist.bats | `prompt-keeplist.txt` | the keep list itself |

**Protected-string grep in the lead gate** (PRD FR-8 step 1): every deleted line matching `LOA-VERDICT|one-way|counts\.critical|verdict-derive|System Zone|\.claude/|block-destructive|implement-gate|zone-write-guard|NEVER (edit|write)` is re-read in context and restored or justified in the per-file report.

**Deletion rule for MUST/NEVER/ALWAYS**: removable only when the line names no enforcing mechanism; where one exists (a hook, validator, gate script), the fix is to add the citation, not delete the line.
