---
schema_version: 1.0
from: opus-4-7-cycle-104-sprint-2-partial-orchestrator
to: cycle-104-sprint-2-continuator
topic: sprint-2-partial-handoff
status: ready
provenance:
  cycle: cycle-104-multi-model-stabilization
  sprint: sprint-2
  predecessor_pr: 849
  branch: feature/cycle-104-sprint-2-fallback-chains-headless
  commits: [241c703e, 42857c72]
last_updated: 2026-05-12T13:00:00Z
tags: [cycle-104, sprint-2, multi-model, fallback-chains, headless, partial-handoff, group-c-deferred]
---

# Cycle-104 Sprint 2 Partial — Groups A + B Shipped → Group C Continuation

## TL;DR

Sprint 2 (14 tasks total, LARGE scope) landed Groups A+B autonomously this session as a stacked branch off PR #849. **4/14 tasks committed.** Routing substrate (T2.1+T2.2) + config layer (T2.3+T2.4) are tested, green, and behaviorally complete in isolation. Operator-gated tasks (T2.10 + T2.11) blocked as expected. Group C (T2.5 cheval.invoke wiring + T2.6 MODELINV envelope v1.1) deliberately deferred — see §"Why Group C halted".

## Where to pick up cold

Read in order:

1. **`grimoires/loa/known-failures.md`** — KF-003 (the load-bearing closure target for this sprint). After Group C lands and T2.10 runs, KF-003 attempts row should record the within-company chain absorption evidence.

2. **`grimoires/loa/NOTES.md`** head section — Decision Log for this partial run includes the SDD §10 Q6 audit finding on `retry.py × EmptyContentError`.

3. **GitHub artifacts**:
   - PR #849 (Sprint 1) — still draft, will need merge before Sprint 2 rebases to main.
   - Issue #847 — Sprint 2 anchor with 8 ACs / 10 PRD tasks.

4. **Cycle artifacts** (unchanged from Sprint 1 handoff):
   - `prd.md` §4 FR-S2.*
   - `sdd.md` §1.4.1, §1.4.2, §3.1, §3.2, §3.3, §3.4, §5.1, §5.2, §5.3, §10 Q6+Q7
   - `sprint.md` lines 113-216

## Branch / commit state

| Item | Value |
|------|-------|
| Branch | `feature/cycle-104-sprint-2-fallback-chains-headless` |
| Stacked off | `feature/cycle-104-sprint-1-archive-hygiene` (PR #849 draft, unmerged) |
| Commits ahead of sprint-1 HEAD | 2 |
| Commits ahead of main | 7 (4 from Sprint 1 + 2 from Sprint 2 + 1 commit count delta from --no-verify mechanics) |
| Sprint 1 PR | #849 (draft) — must merge first or rebase Sprint 2 onto main after merge |
| Sprint 2 PR | NOT created yet (sprint not complete) |
| Sprint 2 in ledger | `status: pending` (do NOT mark completed until Group C+E+G+operator-gated land) |

## Group / task status table

| Group | Tasks | Status | Commit |
|-------|-------|--------|--------|
| A — Routing substrate | T2.1 chain_resolver.py + T2.2 capability_gate.py | ✅ SHIPPED | 241c703e |
| B — Config layer | T2.3 fallback_chain + T2.4 headless aliases | ✅ SHIPPED | 42857c72 |
| C — Integration | T2.5 cheval.invoke wiring + T2.6 MODELINV v1.1 | ⏳ DEFERRED | — |
| D — Operator control | T2.7 hounfour.headless.mode + LOA_HEADLESS_MODE | 🟡 PARTIAL — config example doc shipped (42857c72); cheval consumption deferred to Group C | partial |
| E — Cross-company repurpose + revert | T2.8 voice-drop + T2.9 code_review revert | ⏳ DEFERRED — T2.9 gated on T2.10 (R8) | — |
| F — Empirical + e2e | T2.10 KF-003 replay + T2.11 cli-only e2e | 🚫 OPERATOR-GATED | — |
| G — Docs + cleanup | T2.12 runbooks + T2.13 cross-runtime parity + T2.14 LOA_BB_FORCE_LEGACY_FETCH removal | ⏳ DEFERRED | — |

## Why Group C halted

`cheval.invoke()` is 1057 LOC. The single-model dispatch path (lines 575-720) is woven into:
- Per-call input-size gate (KF-002 layer 3 backstop)
- Budget hook (BudgetEnforcer pre_call / post_call)
- `--mock-fixture-dir` test bypass
- Async-mode (`create_interaction` for Deep Research)
- `invoke_with_retry` (per-adapter retry budget)
- MODELINV emit state machine (try/finally with `_modelinv_state` mutation)

Wiring `chain_resolver.resolve()` upfront and replacing the single-model dispatch with a chain-walk loop is an architectural refactor. Each chain entry needs:
- Its own adapter dispatch (provider may differ between entries — `gpt-5.5-pro` HTTP vs `codex-headless` subprocess)
- Capability gate check
- Per-entry input-size gate evaluation (different `max_input_tokens` per model)
- `models_failed[]` append on retryable error
- Schema-bumped MODELINV envelope (`final_model_id`, `transport`, `config_observed.headless_mode`, `headless_mode_source`)

**Doing this in one session against a 1057-LOC dispatch function carries non-trivial regression risk.** The session-budget-vs-risk tradeoff favors landing Groups A+B as a clean checkpoint and treating Group C as its own focused work unit.

The senior-lead pattern from Sprint 1 close: don't bundle architectural surgery into a PR that already has shippable value. **Partial-sprint PR for operator review is the right shape.**

## Concrete starting point for next session

Recommended sequence:

1. **Read this file** + `sdd.md` §5.3 (cheval.invoke integration pseudocode).
2. **Audit `cheval.py:447-720`** (`cmd_invoke` body). Identify the exact insertion points:
   - Just after `resolve_execution` returns (~line 460): call `chain_resolver.resolve(primary_alias, ...)` to get `ResolvedChain`.
   - Replace the single-model dispatch (lines 631-718) with a chain-walk loop.
3. **MODELINV schema bump** in `.claude/adapters/loa_cheval/audit/modelinv.py`. Schema version goes `1.0 → 1.1`; consumers ignore unknown fields per cycle-098 envelope invariant.
4. **Tests**: `test_chain_walk_audit_envelope.py` with mocked adapters that raise `EmptyContentError` in sequence — verify the walk records `models_failed[]` in order and lands on the final entry. `test_modelinv_envelope_chain_walk.py` pins the schema-1.1 shape.
5. **Don't refactor retry.py**. The audit finding (§"SDD §10 Q6" in NOTES.md head) explains why — chain walk catches `EmptyContentError` at the right layer.

After Group C lands:
- Group D consumption (T2.7): cheval call site uses `resolve_headless_mode()` helper that already shipped in Group A.
- Group E (T2.8 voice-drop + T2.9 code_review revert with R8 gate).
- Group F operator-gated: pause for operator.
- Group G docs + parity.
- `/review-sprint sprint-2` + `/audit-sprint sprint-2` + draft PR + ledger update.

## Test inventory

| Suite | LOC | Tests | Coverage |
|-------|-----|-------|----------|
| test_chain_resolver_within_company.py | 204 | 15 | within-company invariant, duplicate detection, alias indirection, immutability, idempotency, unknown-kind, empty-spec rejection |
| test_chain_resolver_modes.py | 250 | 16 | 4-mode shape distinctness, cli-only fail-loud, env > config > default precedence, stable-order property |
| test_capability_gate.py | 160 | 15 | conservative inference, override semantics, frozen-result, skip-vs-raise contract |
| test_model_config_fallback_chain_invariants.py | 183 | 8 | lints live `.claude/defaults/model-config.yaml` — every primary chain resolves within-company, headless aliases present, terminals correct |
| **Total** | **797** | **54** | |

Plus pre-existing flatline-routing pass count restored from 13/23 → 22/23 (the 1 remaining failure pre-dates Sprint 2 — CLI argument issue in `test_validate_bindings_includes_new_agents`).

## Iron-grip gate reminders for the continuator

- **Continue on `feature/cycle-104-sprint-2-fallback-chains-headless`** (do NOT switch off; Group A+B commits live there).
- **--no-verify still pre-authorized** for cycle-104 commits (KF-005 beads MIGRATION_NEEDED).
- **Sprint 2 PR creation waits until Group C+E+G land.** Stacked PR shape: one PR for the whole sprint.
- **T2.9 (code_review revert) MUST sequence after T2.10 (KF-003 replay) passes** (R8). Don't revert in advance.
- **AC-2.1 lint is now load-bearing**: any future edit to `model-config.yaml` that introduces a cross-company chain entry will fail `test_model_config_fallback_chain_invariants.py`. Run pytest before committing.

## Out of scope for this partial run (explicit reminders)

- Bedrock chains (deliberately out of cycle-104; separate dispatch path).
- Prompt-dialect translation between companies (cycle-102 SKP-002, deferred).
- Sprint 3 work (verification + drift-gate ext + KF-008 replay).

## Risks observed but not realized

| Risk | Status |
|------|--------|
| R8: T2.9 reverts code_review without T2.10 evidence | Avoided — T2.9 not landed |
| R9: cross-runtime parity regresses on `kind: cli` | Likely safe — `gen-adapter-maps.sh --check` is green; T2.13 corpus extension is its own task |
| R-Q6: `EmptyContentError` not retryable in retry.py | Documented + accepted; chain walk catches at the correct layer |

## Stash-safety violation (lesson)

Documented in NOTES.md head section. `git stash pop 2>&1 | tail -3` truncated output that could have hidden a CONFLICT. Files survived because no conflict existed, but the practice was unsafe per `.claude/rules/stash-safety.md`. Future regression-checks against committed state: use `git worktree add` for hermetic comparison.

---

**Status**: READY. Sprint 2 partial committed. Branch persists. Next session continues with Group C.

🤖 Generated as part of cycle-104 Sprint 2 partial run, 2026-05-12
