---
schema_version: 1.0
from: opus-4-7-cycle-104-sprint-1-orchestrator
to: cycle-104-sprint-2-implementer
topic: sprint-2-kickoff
status: ready
provenance:
  cycle: cycle-104-multi-model-stabilization
  sprint: sprint-2
  predecessor_pr: 849
  branch: feature/cycle-104-sprint-1-archive-hygiene
last_updated: 2026-05-12T02:15:00Z
tags: [cycle-104, sprint-2, multi-model, fallback-chains, headless, kf-003]
---

# Cycle-104 Sprint 1 Complete → Sprint 2 Handoff

## TL;DR

Sprint 1 (foundational #848 + BB dist gate) **closed and shipped** as draft PR [#849](https://github.com/0xHoneyJar/loa/pull/849). Full quality-gate trail in place:
- /implement: 9 tasks, 19/19 bats tests pass
- /review-sprint: APPROVED with concerns (3 non-blocking)
- /audit-sprint: APPROVED 4.7/5 weighted
- 3 non-blocking follow-ups filed in NOTES.md

**Sprint 2 is the main event** for cycle-104: within-company fallback chains + headless opt-in + revert of cycle-102 T1B.4 code_review swap. **14 tasks, LARGE scope, 5-7 days estimated**. The substrate built by Sprint 1 (archival fix) unblocks cycle-104's own clean archive at ship time.

## Where to pick up cold

Read in order:

1. **`grimoires/loa/known-failures.md`** (per CLAUDE.md context-intake rule). KF-003 (recurrence-3 as of 2026-05-12) + KF-002 + KF-005 (#661 beads bug — operator pre-authorized `--no-verify` for cycle-104 commits) are load-bearing for Sprint 2.

2. **GitHub artifacts**:
   - PR [#849](https://github.com/0xHoneyJar/loa/pull/849) — Sprint 1 (this PR). Body has the full implement/review/audit summary.
   - Issue [#847](https://github.com/0xHoneyJar/loa/issues/847) — Sprint 2 anchor. 8 ACs, 10 PRD tasks, full proposed architecture.

3. **Cycle artifacts**:
   - `grimoires/loa/cycles/cycle-104-multi-model-stabilization/prd.md` (312 lines) — §4 FR-S2.* for Sprint 2 functional requirements
   - `grimoires/loa/cycles/cycle-104-multi-model-stabilization/sdd.md` (910 lines) — §1.4.1 (chain_resolver), §1.4.2 (capability_gate), §1.4.6 (model-config schema), §3.* (data shapes), §5.* (impl spec), §6.1+§6.5 (error handling + voice-drop), §7.4 (KF-003 replay), §10 (open questions + sprint 3 reframe)
   - `grimoires/loa/cycles/cycle-104-multi-model-stabilization/sprint.md` lines 113-216 — Sprint 2 task list + AC mapping

4. **Sprint 1 trail** (the gates that just closed):
   - `grimoires/loa/cycles/cycle-104-multi-model-stabilization/a2a/sprint-1/reviewer.md` — implementation report
   - `grimoires/loa/cycles/cycle-104-multi-model-stabilization/a2a/sprint-1/engineer-feedback.md` — senior lead review (3 non-blocking concerns documented)
   - `grimoires/loa/cycles/cycle-104-multi-model-stabilization/a2a/sprint-1/auditor-sprint-feedback.md` — security+quality audit

5. **NOTES.md Decision Log** — `grimoires/loa/NOTES.md` head section has Sprint 1 closure entry + 3 follow-ups + 2 patterns to propagate (LOA_REPO_ROOT bats pattern, realpath canonicalization).

## Branch / git state

| Item | Value |
|------|-------|
| Branch | `feature/cycle-104-sprint-1-archive-hygiene` (still on it — DO NOT switch off) |
| Current HEAD | `6f82cd6c` (Sprint 1 close commit) |
| Commits ahead of main | 4 (`aab8f82d` + `84771cef` + `d66c66f0` + `6f82cd6c`) |
| Sprint 1 PR | [#849](https://github.com/0xHoneyJar/loa/pull/849) (draft) |
| Sprint 1 in ledger | `status: completed, pr: 849, completed: 2026-05-12T02:09:00Z` |
| Sprint 2 in ledger | `status: pending` (waiting on implement) |

**Convention decision**: Per cycle-104 PRD §6.2, Sprint 1 lands as its own PR rather than consolidated. This was chosen because:
- KF-005 (#661 beads migration bug) forced manual orchestration anyway
- Iron-grip gate discipline: each sprint should have its own full review+audit trail
- Sprint 2 + Sprint 3 can land on the SAME branch as a follow-up PR (or merge Sprint 1 first and rebase)

Sprint 2 implementer's choice: continue on `feature/cycle-104-sprint-1-archive-hygiene` (keep stacked) OR cut new branch `feature/cycle-104-sprint-2-fallback-chains` off main after #849 merges. Recommend: stacked branch for now; rebase after #849 merges.

## Sprint 2 scope (verbatim from sprint.md)

**Goal**: Populate `fallback_chain` system-wide in `model-config.yaml`; add headless aliases with capability gate; ship `hounfour.headless.mode` (4 modes); revert cycle-102 T1B.4 cross-company swap so 3-company BB consensus diversity is restored AND KF-003 is absorbed within-company.

**Scope**: LARGE (14 technical tasks T2.1 through T2.14)
**Duration**: 5-7 days
**Issue**: [#847](https://github.com/0xHoneyJar/loa/issues/847) — 8 ACs / 10 PRD tasks (mapped + 4 SDD-derived additions)
**Cycle-exit goals**: G1 (3-company diversity), G2 (KF-003 within-company absorption), G3 (operator-opt-in headless), G4 (cli-only zero-API-key end-to-end)

**Critical sequencing constraint (R8)**: T2.10 (KF-003 empirical replay) MUST pass BEFORE T2.9 (code_review revert). Reverting `flatline_protocol.code_review.model` from `claude-opus-4-7` back to `gpt-5.5-pro` only works once the within-company chain demonstrably absorbs KF-003 — otherwise we re-introduce the failure class.

## Task grouping suggestion (for the implementer)

| Group | Tasks | Why grouped |
|-------|-------|-------------|
| **A. Routing substrate** | T2.1 chain_resolver.py + T2.2 capability_gate.py | Both new files under `.claude/adapters/loa_cheval/routing/`. Self-contained Python + dataclasses + unit tests. SDD §5.1, §5.2. ~400-600 LOC. |
| **B. Config layer** | T2.3 fallback_chain population + T2.4 headless aliases | `.claude/defaults/model-config.yaml` edits. Schema invariant: no cross-company chain entries (Sprint 2 AC-2.1). Reuses cycle-099 alias-resolution corpus for testing. |
| **C. Integration** | T2.5 cheval.py invoke() + T2.6 MODELINV envelope schema v1.1 | Wires substrate into cheval. Audit envelope additive-only changes. SDD §5.3, §3.4. |
| **D. Operator control** | T2.7 hounfour.headless.mode + LOA_HEADLESS_MODE | Config + env var + 4 modes (prefer-api / prefer-cli / api-only / cli-only). |
| **E. Cross-company repurpose + revert** | T2.8 voice-drop + T2.9 code_review revert | T2.8 is the adversarial-review.sh change; T2.9 is the load-bearing revert. T2.9 MUST come after T2.10. |
| **F. Empirical + e2e tests** | T2.10 KF-003 replay + T2.11 cli-only zero-API-key | Live-API gated (`LOA_RUN_LIVE_TESTS=1`). Budget ≤$3 total (PRD §7.4). Closes KF-003 attempts row with empirical evidence. |
| **G. Docs + cleanup** | T2.12 runbooks (headless-mode + capability-matrix) + T2.13 cross-runtime parity + T2.14 remove LOA_BB_FORCE_LEGACY_FETCH | Closer to ship-prep. |

## Concrete starting point for /implement sprint-2

Recommended first /implement invocation focus: **Groups A+B+C** (substrate + config + integration). This is the load-bearing core. Once it lands, Groups D-G are incremental.

Brief template:
```
sprint-2 — Cycle-104 Sprint 2 (Within-Company Fallback Chains + Headless Opt-In + code_review Revert)
Substrate first: T2.1+T2.2+T2.5 (chain_resolver + capability_gate + cheval.py wiring)
Then config: T2.3+T2.4 (model-config.yaml fallback_chain for every primary + headless aliases)
Then audit: T2.6 (MODELINV schema v1.1 additive)
HOLD T2.9 (code_review revert) UNTIL T2.10 (KF-003 empirical replay) passes (R8)
Beads MIGRATION_NEEDED (KF-005); TaskCreate-only fallback per cycle-102 precedent; --no-verify pre-authorized for commits.
```

## Carry-forwards from Sprint 1 review/audit

These are **already documented as non-blocking** but worth integrating into Sprint 2 if convenient:

1. **`find -printf` macOS portability** — if Sprint 2 touches any new bash-find usage, use the SDD §5.5 portability constraints. Consider adding a `tools/lib/portable-find.sh` helper.

2. **`dist/.build-manifest.json` pre-verification UX** — Sprint 2's BB-touching tasks (T2.5 wiring) will trigger the drift gate. After T2.5, run `npm run build` to regenerate the manifest. Operator-friendly to include the manifest update in the same commit as the TS changes.

3. **`LOA_REPO_ROOT` bats pattern** — Sprint 2's tests will need the same hermetic-isolation pattern when testing bootstrap-using scripts. Pattern is documented in Sprint 1 reviewer.md §Technical Highlights. Worth extracting to `.claude/rules/bats-hermetic-tests.md` as a Sprint 2 side-task.

4. **`get_current_cycle()` pre-existing bug** — if Sprint 2 lands a fix opportunistically, that's a freebie. Otherwise file as sprint-bug.

## Iron-grip gate reminders for Sprint 2

- **/implement → /review-sprint → /audit-sprint loop required** (per CLAUDE.md NEVER rule)
- **Flatline review on PRD/SDD/sprint deliverables** if the cycle-104 PRD's recursive-dogfood pattern recurs at Sprint 2 close (KF-003 may re-fire on Sprint 2 reviewer.md if it exceeds 27KB; that's actually GOOD evidence the cycle's premise is sound).
- **AC-2.1 invariant validator** (every primary's chain validated against no-cross-company): make this a load-time check, NOT just a test (per SDD §5.1).
- **T2.10 must pass before T2.9** (R8). Test order matters.
- **JCS canonicalization** for new audit payloads (`lib/jcs.sh` — NEVER substitute `jq -S -c`, cycle-098 invariant).

## Environment / preconditions

- `node v20.19.2` + `npm 9.2.0` confirmed working on host
- `bats 1.11.0` available at `/tmp/bats-install/bats-core-1.11.0/bin/bats` (not in PATH — Sprint 2 bats tests will need this or apt install bats)
- `beads_rust` status: MIGRATION_NEEDED (KF-005). Operator pre-authorized `--no-verify` for cycle-104 commits.
- BB rebuild verified clean as of 2026-05-12 (source_hash `f773359d45f52bfbce5daa96a2868e3b7c4500663df4c8927f179928e9b79a73`)

## Open decisions deferred from Sprint 1

None blocking. All Sprint 1 questions resolved at audit close.

## Out of scope for Sprint 2 (explicit reminders)

- New provider companies (xAI, Mistral). Within-company chains assume the existing Anthropic/OpenAI/Google triad.
- Prompt-dialect translation between companies (SKP-002 from cycle-102 sprint-Flatline). Deferred to a future cycle.
- BB internal multi-model dispatcher → cheval routing (that's **Sprint 3** scope, and per SDD §10 Q1+Q2 reframing, it's verification + drift gate ext + KF-008 substrate replay — NOT a migration since BB already routes through `ChevalDelegateAdapter`).

---

**Status**: READY. Sprint 1 closed. Branch + PR persisted. Sprint 2 can start in a fresh context window.

🤖 Generated as part of cycle-104 Sprint 1 close, 2026-05-12
