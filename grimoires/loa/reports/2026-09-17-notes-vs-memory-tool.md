# Decision memo — keep NOTES.md; do not adopt the `memory_20250818` tool (cycle-124, FR-10)

**Date**: 2026-09-22 (decision scoped in the cycle-124 PRD of 2026-09-17) · **Status**: decided · **Owner**: framework maintainers

## Decision

Loa keeps `grimoires/loa/NOTES.md` as its per-operator session memory, bounded by `notes-guard.sh` (100 KiB warn, 200 KiB block, heading-based default read, tested rotation). Loa does **not** adopt the Anthropic `memory_20250818` client tool.

## Why

1. **It is a client-side tool, not a service.** `memory_20250818` gives the model `view/create/str_replace/insert/delete/rename` commands against a `/memories` directory that the *caller* implements — the backend store, path canonicalization and directory-traversal checks are the integrator's code. Adopting it means writing and securing a memory filesystem, then wiring it into every dispatch that should remember. NOTES.md already is that store, with the fences this sprint adds.
2. **Loa has no resident multi-turn loop to attach it to.** The only Messages-API surface is `cheval`, and it issues one-shot completions (one request, one envelope) for review, audit, scoring and dissent. A memory tool earns its keep inside a long-running agent loop that reads and writes memory across turns; a one-shot dispatcher would pay the tool-schema tokens on every call and never benefit.
3. **Cross-session facts already have stronger homes.** Recurring failures go to the known-failures ledger (`kf-write-lib.sh`, append-only, evidence-bearing), task state to beads, trust and handoffs to the agent-network GT files, and operator-personal recall to the harness's own auto-memory. NOTES.md carries the per-cycle working state the recovery protocol reads first. A second free-form store would split that authority order (`session-continuity.md` §Order of authority) without adding a capability.
4. **Security posture.** A model-writable memory directory is a new prompt-injection sink (anything a model reads later becomes an instruction candidate). NOTES.md is untracked per-operator state read through the zone model; the framework already treats L5/L6/L7 bodies as untrusted at surfacing. Extending that discipline to a second store is cost without a consumer.

## What FR-10 delivers instead

- `.claude/scripts/notes-guard.sh` — `check` (size gate with `--delta`), `read` (Blockers + newest Session Continuity + 3 newest Decision Logs, ≤ 68 KiB, loud drift fallback), `rotate` (archive fsynced before the live rewrite; existing target refused; never `git stash`).
- Fences: `notes-size-guard.sh` (PreToolUse Write/Edit/MultiEdit, direction-aware), `FR-NOTES` in `block-destructive-bash.sh` for `>>` appends, and the writer-side gate in `update-notes-learnings.sh`.
- Readers: the session-recovery Level 1/3 recipes and the ride/translate readers go through `notes-guard.sh read`.

## Revisit triggers

- `cheval` (or a successor) grows a resident multi-turn agent loop that needs memory between turns.
- Loa adopts a managed-agent runtime with a hosted memory store (server-side, not caller-implemented).
- The bounded NOTES.md proves insufficient in practice: repeated rotations losing decisions the recovery read needed (evidence: KF entries citing lost Decision Log context after a rotation).

## Provenance

PRD FR-10 (5), SDD §3.7; sprint-238 (Sprint 4) of cycle-124. No operator content in this memo.
