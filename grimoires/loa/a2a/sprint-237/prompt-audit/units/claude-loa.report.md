# Prompt audit report — `claude-loa` (`.claude/loa/CLAUDE.loa.md`, lead-authored, landed in `c6ac82f4`)

**Target model**: Claude Fable 5.1. **Bytes**: 22,005 → 10,222 (budget 10,240). Assembled by `scratchpad/assemble-claude-loa.py`; the header hash was restamped so the mount checksum stays honest.

**Method**: the verbatim regions that no summary may touch — the registry-rendered NEVER/ALWAYS/Merge/Agent-Teams tables, the Three-Zone table, the Golden Path and truename tables, the Reference-Files table, the agent-network universal invariants — total 7,933 B on their own (the PRD's 9,813 estimate omitted the tables), so the kernel is ~700 B of Karpathy text plus one sentence per remaining section. Every section that used to carry a paragraph or a sub-table now carries one sentence and a pointer row: run-mode recovery, session-limit capture, hooks/fences, beads-first, Flatline, multi-model, tiered dispatch, post-PR, post-merge.

| Region | Pattern | Action |
|---|---|---|
| Karpathy Principles (~4.9 KB) | 1c canonical text duplicated across surfaces | kernel (four names, the ladder, the never-simplify floor, `loa:shortcut:`, `simplicity_intensity`); full text moved to `.claude/protocols/karpathy-principles.md` v3.0 |
| Process Compliance prose around the tables | 1c restatement of the rendered rows | removed; tables byte-identical (`generate-constraints.sh --dry-run` empty) |
| Run Mode State Recovery / Post-Compact / Session-Limit / Run Bridge / BUTTERFREEZONE / Guardrails / Prompt Enhancement / Retrospective sections | 1c pointer-worthy detail loaded every session | one sentence each; detail lives in the reference files already listed |
| `(cycle-122)`, `(cycle-119)`, `issue #1177 item F` in rule text | 1d history tokens | removed here and in `.claude/data/constraints.json` / `skill-includes/input_guardrails.md` so the rendered rows regenerate identically |

Keep-list: every K-row pointing at CLAUDE.loa.md (reference rows, zone table, golden path, agent-network invariants, Agent Teams MUST rows, beads-first) survives byte for byte (`prompt-audit-keeplist.bats` green). Untrusted input: none.
