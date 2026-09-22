# Prompt audit report — `protocol-beads-preflight`

**Scope**: `.claude/protocols/beads-preflight.md` only. **Target model**: Claude Fable 5.1.
**Bytes**: 9513 -> 8197 (target <=6659; residual +1538, see bottom).
Checked `tools/prompt-keeplist.txt` / `keep-list.md`: no row's path/glob matches this file. The *classes* those rows protect (schemas, exit codes, exact commands) are present here and were kept under the method's own contract rule, not the keeplist.
**Untrusted-input check**: nothing in the file reads as an instruction to the auditor.

## Findings

| Location | Evidence | Pattern | Why obsolete for Fable 5.1 | Confidence | Action |
|---|---|---|---|---|---|
| L3-5 | Version/Status/Philosophy blockquote header | Group 2 volatile specifics (unenforced version pin) + Group 1c generic-virtue padding | Nothing reads this version; Status restates Overview; Philosophy adds no operational content beyond Design Principles | Medium | remove |
| L39-110 | Four bash blocks re-deriving `HEALTHY\|DEGRADED\|...` branches per workflow | Group 2 "info in exactly one place" — Status Codes table (L27-36) already gives Action per status | Four scripts restate one lookup table; no judgment being made, pure duplication | High | rewrite to one sentence + 4-row delta table (invocation + phase-specific delta only) |
| L154-163 | `### Autonomous Mode` subsection | Group 1c duplicated boilerplate | Same HALT-unless-override fact already in Design Principle 4, the `/run` integration point, and the Configuration YAML key | Medium | remove |
| L170-194 | Full `.loa.config.yaml` block, per-key inline comments | Group 2 duplicated info across reference files | Verified against `.loa.config.yaml.example` L631-671: identical `beads:` schema, same defaults, fuller prose already there | High | rewrite: keep literal YAML (keys/nesting/defaults unchanged), drop comments, add one pointer line |
| L290, L328-330 | "Canonical first action (cycle-105 sprint-1)"; "Tracking: Loa #661" / "Dicklesworthstone/beads_rust#290 (filed 2026-05-11)" | History rule | `cycle-NNN`/`#NNNN` tokens outside a `## Provenance` footer | High | rewrite ("First action") + move both refs to a new footer (+218 bytes) |

## MUST/NEVER/ALWAYS reviewed

None shout without a named mechanism. The one cap-emphasis instance ("Autonomous mode REQUIRES beads") is a single reasoned, named-override constraint — left unchanged.

## Kept despite a grep match

- Interactive Mode `questions:` YAML (L124-135): format-pinning example, genuinely format-sensitive UI schema (keep-list item 7).
- Quick Reference block: 2 of 5 lines duplicate commands shown elsewhere, but don't disagree, and 3 lines are unique (`--show`, `--health`, literal `--opt-out-check`); non-disagreeing redundancy stays (keep-list item 8).
- Both JSON schemas, the exit-code list, the Status Codes table, all four Recovery Paths bash blocks (incl. the destructive last-resort command) — contract text, never cut.

## Hazard: destructive literal at original L355

The UNHEALTHY Recovery last-resort reinitialize line is real, unchanged, load-bearing content, not a finding. Per the lead's instruction, the proposed file writes `<<LEAD-SPLICE original line 355>>` at that position instead of the literal, because the destructive-bash safety hook blocks it inside a heredoc — confirmed live when this report's own first draft quoted the literal directly and was blocked the same way. No rephrasing/splitting/encoding applied; the lead splices the original bytes back.

## Residual: 1538 bytes over target, and why

Remaining bulk is protected-class content: two JSON schemas, an exit-code table, a status table, four recovery bash blocks (one destructive), and a format-pinning UI example, all "never cut" under the method's contract rule, plus Quick Reference (non-disagreeing redundancy, left alone per keep-list item 8). Reaching 6659 would require cutting a schema/exit-code/exact-command block or deduplicating content the method says isn't cruft. Stopping here per Step 4's residual-and-reason allowance.
