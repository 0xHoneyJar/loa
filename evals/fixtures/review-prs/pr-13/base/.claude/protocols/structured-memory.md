# Structured Agentic Memory Protocol (NOTES.md)

What a model cannot infer is WHERE durable notes go — that is the contract this file carries.

## Where durable knowledge goes

| Knowledge | Home | Why not NOTES.md |
|-----------|------|------------------|
| Current-cycle working state, decisions, blockers | `grimoires/loa/NOTES.md` (untracked per-operator state) | — |
| Failure patterns with recurrence evidence | `grimoires/loa/known-failures.md` via `kf-write-lib.sh` | compounds across sessions/team |
| User preferences, session narrative, discovered patterns | Claude Code auto-memory | per-user, harness-managed |
| Task lifecycle | beads (`br`) | single source of truth |
| Ground truth / API surface | `grimoires/loa/gt/` (generated) | machine-verified citations |

## Required Sections (NOTES.md template)

`.claude/templates/NOTES.md.template` is the mechanical carrier for new mounts: Current Focus, Session Log, Decisions, Blockers, Technical Debt, Goal Status, Learnings, Session Continuity. `check-loa.sh check_notes_template` WARNs (never fails) when the live file lacks **Session Continuity** or **Decision Log** — the two recovery-critical sections KF forensics depend on (the known-failures.md attempts tables cite Decision Log entries).

## Agent Discipline (when to write)

| Event | Write |
|-------|-------|
| Session start | read Session Continuity first |
| Decision made | Decision Log entry, immediately (not at session end) |
| Blocker hit / Blocker resolved | Blockers section |
| Mistake discovered | Learnings (or KF ledger if recurrence-worthy) |
| Session end / pre-compaction | update Session Continuity |
| File reaches 100 KiB / 200 KiB | `notes-guard.sh check` warns at 100 KiB and refuses growth at 200 KiB (hook, `>>` fence, learnings writer); run `/compound` or `notes-guard.sh rotate` (archive first, keep the `read` selection) |

Recovery procedure (tiered L1/L2/L3, default read = `notes-guard.sh read`, ≤ 68 KiB): `.claude/protocols/session-continuity.md`. Clearing thresholds + synthesis format: `.claude/protocols/tool-result-clearing.md`.

## Provenance

v0.16.0 required sections and agent discipline; v0.9.0 session-continuity integration; v2.0 shrink to the load-bearing contract in cycle-121.
