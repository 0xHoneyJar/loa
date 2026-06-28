---
paths:
  - "grimoires/**"
  - ".beads/**"
  - ".ck/**"
  - ".run/**"
origin: genesis
version: 1
enacted_by: cycle-049
---

# State Zone Rules

The State Zone (`grimoires/`, `.beads/`, `.ck/`, `.run/`) stores session-spanning state. Read/Write permitted.

- **Grimoires**: Planning artifacts (PRD, SDD, sprint), context docs, memory, observations
- **Beads**: Task tracking state (managed by `br` CLI)
- **Run**: Autonomous execution state (sprint-plan-state, bridge-state, simstim-state)
- Configurable paths via `.loa.config.yaml`: `LOA_GRIMOIRE_DIR`, `LOA_BEADS_DIR`
- Memory observations: `grimoires/loa/memory/observations.jsonl` — queried via `.claude/scripts/memory-query.sh`
- In Agent Teams mode, only the lead writes to `.run/*.json` (teammates report via SendMessage)

## OKF interop boundary (cycle: OKF/ICM adoption, 2026-06-28)

OKF (Open Knowledge Format) **fail-soft consumption** — SPEC §5.3/§9: consumers MUST tolerate broken links and missing fields as "not-yet-written knowledge" — **MUST NOT be imported into any loa validator or decision gate.** Within loa, dangling internal references remain **defects** and grounding checks (cite `file:line`) stay **fail-closed**. OKF is supported only as a derived **export** projection (downstream of every gate) and, if ever ingested, only under the parse-soft / promote-strict ingest contract (`grimoires/loa/proposals/okf-ingest-contract-2026-06-28.md`). Rationale: PR #1155 analysis §7–§8.
