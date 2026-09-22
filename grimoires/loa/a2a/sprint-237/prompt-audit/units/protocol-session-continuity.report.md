# Prompt audit report — `protocol-session-continuity`

**Scope**: `.claude/protocols/session-continuity.md` only. **Target**: Claude Fable 5.1. **Bytes**: 24,138 → 14,518 (−39.9%; target ≤16,896). No keep-list row (`tools/prompt-keeplist.txt`, `keep-list.md`) matches this path — every finding's keep-list check is "N/A, no row applies." No `@constraint-generated`/`@skill-include` markers present. No `cycle-NNN`/`#NNNN`/`KF-NNN` tokens present, so no `## Provenance` footer was added. **Untrusted-input check**: file has no text addressed to the auditing agent; nothing ignored/flagged.

Top findings: a 62-line ASCII "Protocol Dependency Diagram" fully duplicating the three plain lists right after it; a second ASCII "FORK DETECTION PROTOCOL" box duplicating the earlier prose Fork Detection; pervasive version stamps (`v0.11.0`, `v0.9.0`, `v1.27.0`, `v0.19.0`, `v2.3`, "Backwards Compatibility"/"Migration: No migration required") narrating the file's own history instead of stating current rules.

| Location | Pattern | Evidence | Why obsolete | Confidence | Action |
|---|---|---|---|---|---|
| L512-575 | 1c/2 dup | "PROTOCOL DEPENDENCY DIAGRAM" box | Restates the lists 3 lines later | High | remove |
| L3-4,647-649 | 1d history | "Version 1.1 (v0.11.0…)", footer version block | Revision narration, nothing reads it | High | remove |
| L10-12,98,249,393 | 1d migration phrasing | "As of v0.11.0…", "(v1.27.0)", "(v0.9.0…)", "for v0.19.0" | "As of X" implies a phantom prior state | High | remove |
| L58-70,146-154,180-192 | 1a shouting | "IMMUTABLE TRUTH HIERARCHY", "CONTINUOUS SYNTHESIS:", "SYNTHESIS CHECKPOINT (BLOCKING)" all-caps | No need to shout a 7-item order or a checklist; content/thresholds kept | High | rewrite to prose/plain list |
| L367-390 | 1c/1d dup | "FORK DETECTION PROTOCOL" box | Duplicates L73-78 prose; only the JSONL line was new | High | rewrite (prose + kept JSONL example) |
| L406-459 | 1c/2 fabricated output | "Output includes: … comments: - [ts] DECISION:…" | Unverified sample CLI output, re-teaches the CLI table row by row | Medium | remove (kept the one `DECISION:`/`Rationale:`/`Evidence:` format example) |
| L356-365 | 1d migration phrasing | "Migration: No migration required" | Past-transition narrative; only the default-value rule is forward-looking | Medium | rewrite → one-line "Defaults" |
| L262-263 | 1d migration phrasing | "# EXISTING FIELDS (unchanged)…" | Zero schema content | Medium | remove |
| L275-281,305-309 | 1c near-dup example | 2nd `decisions[]`/`handoffs[]` entries | Structurally identical 2nd example teaches nothing new | Medium | remove (kept `test_scenarios[]`'s 3, which instantiate the min-3 rule) |
| L128-141,465,471,492 | 1c dup comments | `# Load only Session Continuity…`, `# Check if br is available`, etc. | Comment restates the sentence/heading right above it | Medium | remove comments only, script kept |
| L84-116 | 1c dup | Step-0 bullet vs. full "Run Mode State Check" section | Same check stated twice | Medium | rewrite/consolidate |
| L404 | 1c/2 dup | "**Note**: CLI extensions are optional…" | Pre-empted by the Fallback section right after | Medium | remove |
| L239 | 1a shouting | "**REQUIRED**: All paths must use…" | Bold lead-in; example block already carries the rule | Medium | rewrite plain |
| L501-510 | 1a shouting | bold "**NOW**"/"ALWAYS" in Anti-Patterns table | Emphasis on an already-clear rule | Low | rewrite (de-bold) |
| L597-632 | 1c format bleed | fenced ✓ pseudo-diagrams, 3 scenarios | Same info as a plain numbered list | Low | rewrite |

**MUST/NEVER/ALWAYS**: "IF ANY BLOCKING STEP FAILS → REJECT /clear" kept, citing its mechanism (`synthesis-checkpoint.md`, next line). "DO NOT clear context yet" rewritten as "persist without clearing context" — no named mechanism, substance kept. The three "Always …" Anti-Pattern rows kept verbatim, only de-bolded — no mechanism named, not deleted.

**Kept despite grep-matching**: the `<!-- CRITICAL: Load this section FIRST -->` comment inside the "Required Structure" template is literal content meant to be written into `NOTES.md`, not prompt prose — format-pinning, kept byte-for-byte. The `>= 0.95` grounding threshold and "Minimum 3 test scenarios" are named, enforced invariants, not numeric-ceiling choreography. All exact bash/YAML scripts are fragile-bridge operations, kept verbatim.

**Residual**: none — proposed file is ~2,378 bytes under the 16,896 target.
